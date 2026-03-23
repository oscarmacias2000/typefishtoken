// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MiStaking
 * @dev Contrato de staking para MiToken:
 *   - Usuarios depositan tokens y acumulan recompensas por bloque
 *   - El APY lo controla el owner (tú) ajustando rewardRate
 *   - Penalty del 10% si retiran antes del lockPeriod (va al treasury)
 *   - Protegido contra reentrancy
 */

interface ITreasury {
    function sendReward(address to, uint256 amount) external;
}

contract MiStaking is Ownable, ReentrancyGuard {

    IERC20 public immutable token;
    /**address public treasury;**/
    ITreasury public treasury;

    // ─── Config de recompensas ───────────────────────────────
    // rewardRate = tokens por segundo que gana el pool completo
    // Ejemplo: 0.01 tokens/seg con 1000 stakeados = 0.001% por usuario/seg
    uint256 public rewardRate       = 1 * 10**15;   // 0.001 tokens/segundo
    uint256 public lockPeriod       = 7 days;
    uint256 public earlyExitPenalty = 1000;          // 10% (1000/10000)

    // ─── Estado global ───────────────────────────────────────
    uint256 public totalStaked;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    // ─── Estado por usuario ──────────────────────────────────
    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;        // rewardPerToken en el momento del último claim
        uint256 pendingRewards;    // acumulado pero no cobrado
        uint256 stakedAt;          // timestamp del depósito (para lockPeriod)
    }
    mapping(address => StakeInfo) public stakes;

    // ─── Eventos ─────────────────────────────────────────────
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 penalty);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    // ─── Constructor ─────────────────────────────────────────
    constructor(address _token, address _treasury) Ownable(msg.sender) {
        token    = IERC20(_token);
        treasury = ITreasury(_treasury);
        lastUpdateTime = block.timestamp;
    }

    // ─── Modificador: actualiza recompensas antes de cada acción ─
    modifier updateReward(address user) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime       = block.timestamp;
        if (user != address(0)) {
            StakeInfo storage s = stakes[user];
            s.pendingRewards = earned(user);
            s.rewardDebt     = rewardPerTokenStored;
        }
        _;
    }

    // ─── Cálculo de recompensas ──────────────────────────────
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + (
            (block.timestamp - lastUpdateTime) * rewardRate * 10**18 / totalStaked
        );
    }

    function earned(address user) public view returns (uint256) {
        StakeInfo storage s = stakes[user];
        return s.pendingRewards + (
            s.amount * (rewardPerToken() - s.rewardDebt) / 10**18
        );
    }

    // ─── Depositar ───────────────────────────────────────────
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Monto invalido");
        token.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage s = stakes[msg.sender];
        s.amount    += amount;
        s.stakedAt   = block.timestamp;   // reinicia el lock con cada depósito
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    // ─── Retirar ─────────────────────────────────────────────
    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        StakeInfo storage s = stakes[msg.sender];
        require(amount > 0 && amount <= s.amount, "Monto invalido");

        s.amount    -= amount;
        totalStaked -= amount;

        // Penalty si retira antes del lock
        uint256 penalty   = 0;
        uint256 toReceive = amount;
        if (block.timestamp < s.stakedAt + lockPeriod) {
            penalty   = (amount * earlyExitPenalty) / 10_000;
            toReceive = amount - penalty;
            if (penalty > 0) token.transfer(address(treasury), penalty);
        }

        token.transfer(msg.sender, toReceive);
        emit Unstaked(msg.sender, amount, penalty);
    }

    // ─── Cobrar recompensas ──────────────────────────────────
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        StakeInfo storage s = stakes[msg.sender];
        uint256 reward = s.pendingRewards;
        uint256 available = token.balanceOf(address(treasury));

        if(reward > available){
            reward = available;
        }
        require(reward > 0, "Sin recompensas");

        s.pendingRewards = 0;
        // El contrato debe tener tokens para pagar recompensas
        // El owner debe fondear este contrato periódicamente
        treasury.sendReward(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    // ─── Admin ───────────────────────────────────────────────
    function setRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    function setLockPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod <= 30 days, "Lock demasiado largo");
        lockPeriod = newPeriod;
    }

    function setEarlyExitPenalty(uint256 newPenalty) external onlyOwner {
        require(newPenalty <= 2000, "Max 20%");
        earlyExitPenalty = newPenalty;
    }

    // Fondear el contrato con tokens para pagar recompensas
    function fundRewards(uint256 amount) external onlyOwner {
        token.transferFrom(msg.sender, address(this), amount);
    }

    // Vista rápida del estado de un usuario
    function getUserInfo(address user) external view returns (
        uint256 staked,
        uint256 pendingReward,
        uint256 lockEndsAt,
        bool    locked
    ) {
        StakeInfo storage s = stakes[user];
        return (
            s.amount,
            earned(user),
            s.stakedAt + lockPeriod,
            block.timestamp < s.stakedAt + lockPeriod
        );
    }
}
