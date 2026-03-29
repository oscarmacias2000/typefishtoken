// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title TFISHBNBPair
 * @notice Liquidity Pool TFISH/BNB en Polygon
 * @dev AMM simple tipo Uniswap V2 con fees y recompensas
 */
contract TFISHBNBPair is ERC20, Ownable, ReentrancyGuard, Pausable {

    // ═══════════════════════════════════════════
    //  TOKENS
    // ═══════════════════════════════════════════
    IERC20 public immutable tfish;
    IERC20 public immutable bnb;   // BNB bridgeado en Polygon (ERC-20)

    // ═══════════════════════════════════════════
    //  CONFIGURACIÓN
    // ═══════════════════════════════════════════
    uint256 public constant FEE_SWAP      = 30;   // 0.30% fee de swap
    uint256 public constant FEE_PROTOCOL  = 5;    // 0.05% va al treasury
    uint256 public constant FEE_LP        = 25;   // 0.25% va a LPs
    uint256 public constant FEE_DENOM     = 10000;
    uint256 public constant MINIMUM_LIQ   = 1000; // Liquidez mínima bloqueada

    address public treasury;
    uint256 public totalFeesCollected;
    uint256 public totalVolumeUSD;

    // ═══════════════════════════════════════════
    //  RESERVAS
    // ═══════════════════════════════════════════
    uint256 public reserveTFISH;
    uint256 public reserveBNB;
    uint256 public blockTimestampLast;

    // Precios acumulados para TWAP
    uint256 public priceTFISHCumulativeLast;
    uint256 public priceBNBCumulativeLast;

    // ═══════════════════════════════════════════
    //  STAKING DE LP TOKENS
    // ═══════════════════════════════════════════
    struct LPStake {
        uint256 amount;
        uint256 rewardDebt;
        uint256 timestamp;
    }

    uint256 public rewardPerBlock    = 1e15;  // TFISH por bloque como recompensa
    uint256 public accRewardPerShare = 0;
    uint256 public lastRewardBlock;
    uint256 public totalStaked;

    mapping(address => LPStake) public stakes;
    mapping(address => uint256) public feesEarned;

    // ═══════════════════════════════════════════
    //  BRIDGE TRACKING
    // ═══════════════════════════════════════════
    struct BridgeRequest {
        address user;
        uint256 amount;
        string  destChain;   // "BNB_CHAIN"
        string  destAddress;
        uint256 timestamp;
        bool    completed;
        bytes32 txHash;
    }

    mapping(uint256 => BridgeRequest) public bridgeRequests;
    uint256 public totalBridgeRequests;

    // ═══════════════════════════════════════════
    //  EVENTOS
    // ═══════════════════════════════════════════
    event LiquidityAdded(address indexed provider, uint256 tfishAmt, uint256 bnbAmt, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 tfishAmt, uint256 bnbAmt, uint256 lpBurned);
    event SwapTFISHtoBNB(address indexed user, uint256 tfishIn, uint256 bnbOut, uint256 fee);
    event SwapBNBtoTFISH(address indexed user, uint256 bnbIn, uint256 tfishOut, uint256 fee);
    event LPStaked(address indexed user, uint256 amount);
    event LPUnstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 reward);
    event BridgeInitiated(uint256 indexed id, address user, uint256 amount, string destChain);
    event BridgeCompleted(uint256 indexed id, bytes32 txHash);
    event ReservesUpdated(uint256 newTFISH, uint256 newBNB);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════
    constructor(
        address _tfish,
        address _bnb,
        address _treasury
    ) ERC20("TFISH-BNB LP", "TFISH-BNB") Ownable(msg.sender) {
        tfish    = IERC20(_tfish);
        bnb      = IERC20(_bnb);
        treasury = _treasury;
        lastRewardBlock = block.number;
    }

    // ═══════════════════════════════════════════
    //  AGREGAR LIQUIDEZ
    // ═══════════════════════════════════════════
    function addLiquidity(
        uint256 tfishAmount,
        uint256 bnbAmount,
        uint256 tfishMin,
        uint256 bnbMin
    ) external nonReentrant whenNotPaused returns (uint256 lpMinted) {

        require(tfishAmount > 0 && bnbAmount > 0, "Montos invalidos");

        uint256 tfishOptimal = bnbAmount;
        uint256 bnbOptimal   = tfishAmount;

        if (reserveTFISH > 0 && reserveBNB > 0) {
            // Calcular cantidades óptimas manteniendo el ratio
            tfishOptimal = (bnbAmount * reserveTFISH) / reserveBNB;
            bnbOptimal   = (tfishAmount * reserveBNB) / reserveTFISH;

            if (tfishOptimal <= tfishAmount) {
                require(tfishOptimal >= tfishMin, "TFISH insuficiente");
                tfishAmount = tfishOptimal;
            } else {
                require(bnbOptimal >= bnbMin, "BNB insuficiente");
                bnbAmount = bnbOptimal;
            }
        }

        require(tfish.transferFrom(msg.sender, address(this), tfishAmount), "Transfer TFISH fallido");
        require(bnb.transferFrom(msg.sender, address(this), bnbAmount),     "Transfer BNB fallido");

        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            lpMinted = _sqrt(tfishAmount * bnbAmount) - MINIMUM_LIQ;
            _mint(address(this), MINIMUM_LIQ); // Lock mínimo
        } else {
            lpMinted = _min(
                (tfishAmount * totalSupply_) / reserveTFISH,
                (bnbAmount   * totalSupply_) / reserveBNB
            );
        }

        require(lpMinted > 0, "LP insuficientes");
        _mint(msg.sender, lpMinted);
        _updateReserves(reserveTFISH + tfishAmount, reserveBNB + bnbAmount);
        _updateRewards();

        emit LiquidityAdded(msg.sender, tfishAmount, bnbAmount, lpMinted);
    }

    // ═══════════════════════════════════════════
    //  RETIRAR LIQUIDEZ
    // ═══════════════════════════════════════════
    function removeLiquidity(
        uint256 lpAmount,
        uint256 tfishMin,
        uint256 bnbMin
    ) external nonReentrant returns (uint256 tfishOut, uint256 bnbOut) {

        require(lpAmount > 0, "LP invalido");
        require(balanceOf(msg.sender) >= lpAmount, "LP insuficientes");

        uint256 totalSupply_ = totalSupply();
        tfishOut = (lpAmount * reserveTFISH) / totalSupply_;
        bnbOut   = (lpAmount * reserveBNB)   / totalSupply_;

        require(tfishOut >= tfishMin, "TFISH slippage");
        require(bnbOut   >= bnbMin,   "BNB slippage");

        _burn(msg.sender, lpAmount);
        _updateReserves(reserveTFISH - tfishOut, reserveBNB - bnbOut);

        require(tfish.transfer(msg.sender, tfishOut), "Transfer TFISH fallido");
        require(bnb.transfer(msg.sender, bnbOut),     "Transfer BNB fallido");

        emit LiquidityRemoved(msg.sender, tfishOut, bnbOut, lpAmount);
    }

    // ═══════════════════════════════════════════
    //  SWAP TFISH → BNB
    // ═══════════════════════════════════════════
    function swapTFISHtoBNB(
        uint256 tfishIn,
        uint256 bnbOutMin,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 bnbOut) {

        require(tfishIn > 0, "Input invalido");
        require(reserveBNB > 0 && reserveTFISH > 0, "Sin liquidez");

        uint256 feeAmount    = (tfishIn * FEE_SWAP) / FEE_DENOM;
        uint256 protocolFee  = (tfishIn * FEE_PROTOCOL) / FEE_DENOM;
        uint256 tfishInNet   = tfishIn - feeAmount;

        // Formula AMM: x * y = k
        bnbOut = (tfishInNet * reserveBNB) / (reserveTFISH + tfishInNet);
        require(bnbOut >= bnbOutMin, "Slippage excedido");
        require(bnbOut < reserveBNB,  "Liquidez insuficiente");

        require(tfish.transferFrom(msg.sender, address(this), tfishIn), "Transfer fallido");
        require(bnb.transfer(to, bnbOut), "Transfer BNB fallido");

        // Fee al treasury
        if (protocolFee > 0) {
            require(tfish.transfer(treasury, protocolFee), "Fee fallido");
        }

        totalFeesCollected += feeAmount;
        _updateReserves(reserveTFISH + tfishInNet, reserveBNB - bnbOut);

        emit SwapTFISHtoBNB(msg.sender, tfishIn, bnbOut, feeAmount);
    }

    // ═══════════════════════════════════════════
    //  SWAP BNB → TFISH
    // ═══════════════════════════════════════════
    function swapBNBtoTFISH(
        uint256 bnbIn,
        uint256 tfishOutMin,
        address to
    ) external nonReentrant whenNotPaused returns (uint256 tfishOut) {

        require(bnbIn > 0, "Input invalido");
        require(reserveBNB > 0 && reserveTFISH > 0, "Sin liquidez");

        uint256 feeAmount   = (bnbIn * FEE_SWAP)      / FEE_DENOM;
        uint256 protocolFee = (bnbIn * FEE_PROTOCOL)   / FEE_DENOM;
        uint256 bnbInNet    = bnbIn - feeAmount;

        tfishOut = (bnbInNet * reserveTFISH) / (reserveBNB + bnbInNet);
        require(tfishOut >= tfishOutMin, "Slippage excedido");
        require(tfishOut < reserveTFISH,  "Liquidez insuficiente");

        require(bnb.transferFrom(msg.sender, address(this), bnbIn), "Transfer BNB fallido");
        require(tfish.transfer(to, tfishOut), "Transfer TFISH fallido");

        if (protocolFee > 0) {
            require(bnb.transfer(treasury, protocolFee), "Fee fallido");
        }

        totalFeesCollected += feeAmount;
        _updateReserves(reserveTFISH - tfishOut, reserveBNB + bnbInNet);

        emit SwapBNBtoTFISH(msg.sender, bnbIn, tfishOut, feeAmount);
    }

    // ═══════════════════════════════════════════
    //  STAKING DE LP TOKENS
    // ═══════════════════════════════════════════
    function stakLP(uint256 amount) external nonReentrant {
        require(amount > 0, "Cantidad invalida");
        require(balanceOf(msg.sender) >= amount, "LP insuficientes");

        _updateRewards();
        LPStake storage stake = stakes[msg.sender];

        if (stake.amount > 0) {
            uint256 pending = (stake.amount * accRewardPerShare / 1e12) - stake.rewardDebt;
            if (pending > 0) feesEarned[msg.sender] += pending;
        }

        _transfer(msg.sender, address(this), amount);
        stake.amount    += amount;
        stake.timestamp  = block.timestamp;
        stake.rewardDebt = stake.amount * accRewardPerShare / 1e12;
        totalStaked     += amount;

        emit LPStaked(msg.sender, amount);
    }

    function unstakLP(uint256 amount) external nonReentrant {
        LPStake storage stake = stakes[msg.sender];
        require(stake.amount >= amount, "Staked insuficiente");

        _updateRewards();
        uint256 pending = (stake.amount * accRewardPerShare / 1e12) - stake.rewardDebt;
        if (pending > 0) feesEarned[msg.sender] += pending;

        stake.amount    -= amount;
        stake.rewardDebt = stake.amount * accRewardPerShare / 1e12;
        totalStaked     -= amount;

        _transfer(address(this), msg.sender, amount);

        uint256 reward = feesEarned[msg.sender];
        if (reward > 0 && tfish.balanceOf(address(this)) >= reward + reserveTFISH) {
            feesEarned[msg.sender] = 0;
            require(tfish.transfer(msg.sender, reward), "Reward fallido");
        }

        emit LPUnstaked(msg.sender, amount, reward);
    }

    function claimReward() external nonReentrant {
        _updateRewards();
        LPStake storage stake = stakes[msg.sender];
        uint256 pending = (stake.amount * accRewardPerShare / 1e12) - stake.rewardDebt;
        feesEarned[msg.sender] += pending;
        stake.rewardDebt = stake.amount * accRewardPerShare / 1e12;

        uint256 reward = feesEarned[msg.sender];
        require(reward > 0, "Sin recompensas");
        feesEarned[msg.sender] = 0;
        require(tfish.transfer(msg.sender, reward), "Reward fallido");

        emit RewardClaimed(msg.sender, reward);
    }

    // ═══════════════════════════════════════════
    //  BRIDGE TFISH → BNB CHAIN
    // ═══════════════════════════════════════════
    function initiateBridge(
        uint256 amount,
        string calldata destAddress
    ) external nonReentrant whenNotPaused {
        require(amount >= 100e18, "Minimo 100 TFISH para bridge");
        require(bytes(destAddress).length > 0, "Direccion destino invalida");

        require(tfish.transferFrom(msg.sender, address(this), amount), "Transfer fallido");

        totalBridgeRequests++;
        bridgeRequests[totalBridgeRequests] = BridgeRequest({
            user:        msg.sender,
            amount:      amount,
            destChain:   "BNB_CHAIN",
            destAddress: destAddress,
            timestamp:   block.timestamp,
            completed:   false,
            txHash:      bytes32(0)
        });

        emit BridgeInitiated(totalBridgeRequests, msg.sender, amount, "BNB_CHAIN");
    }

    function completeBridge(uint256 requestId, bytes32 txHash) external onlyOwner {
        BridgeRequest storage req = bridgeRequests[requestId];
        require(!req.completed, "Ya completado");
        req.completed = true;
        req.txHash    = txHash;
        emit BridgeCompleted(requestId, txHash);
    }

    // ═══════════════════════════════════════════
    //  VISTAS
    // ═══════════════════════════════════════════
    function getPrice() external view returns (uint256 tfishPerBNB, uint256 bnbPerTFISH) {
        if (reserveTFISH == 0 || reserveBNB == 0) return (0, 0);
        tfishPerBNB  = (reserveTFISH * 1e18) / reserveBNB;
        bnbPerTFISH  = (reserveBNB   * 1e18) / reserveTFISH;
    }

    function getAmountOut(uint256 amountIn, bool tfishToBNB) external view returns (uint256 amountOut, uint256 fee) {
        fee = (amountIn * FEE_SWAP) / FEE_DENOM;
        uint256 amountInNet = amountIn - fee;
        if (tfishToBNB) {
            amountOut = (amountInNet * reserveBNB)   / (reserveTFISH + amountInNet);
        } else {
            amountOut = (amountInNet * reserveTFISH) / (reserveBNB   + amountInNet);
        }
    }

    function getPendingReward(address user) external view returns (uint256) {
        LPStake storage stake = stakes[user];
        if (stake.amount == 0) return feesEarned[user];
        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;
        uint256 acc    = accRewardPerShare + (reward * 1e12 / (totalStaked == 0 ? 1 : totalStaked));
        uint256 pending = (stake.amount * acc / 1e12) - stake.rewardDebt;
        return feesEarned[user] + pending;
    }

    function getPoolStats() external view returns (
        uint256 _reserveTFISH, uint256 _reserveBNB,
        uint256 _totalLP, uint256 _totalStaked,
        uint256 _totalFees, uint256 _totalBridge
    ) {
        return (reserveTFISH, reserveBNB, totalSupply(), totalStaked, totalFeesCollected, totalBridgeRequests);
    }

    // ═══════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════
    function setRewardPerBlock(uint256 _reward) external onlyOwner { rewardPerBlock = _reward; }
    function setTreasury(address _treasury)     external onlyOwner { treasury = _treasury; }
    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function fundRewards(uint256 amount) external {
        require(tfish.transferFrom(msg.sender, address(this), amount), "Transfer fallido");
    }

    // ═══════════════════════════════════════════
    //  INTERNAS
    // ═══════════════════════════════════════════
    function _updateReserves(uint256 newTFISH, uint256 newBNB) internal {
        reserveTFISH       = newTFISH;
        reserveBNB         = newBNB;
        blockTimestampLast = block.timestamp;
        emit ReservesUpdated(newTFISH, newBNB);
    }

    function _updateRewards() internal {
        if (totalStaked == 0) { lastRewardBlock = block.number; return; }
        uint256 blocks = block.number - lastRewardBlock;
        if (blocks == 0) return;
        uint256 reward = blocks * rewardPerBlock;
        accRewardPerShare += reward * 1e12 / totalStaked;
        lastRewardBlock    = block.number;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y / 2 + 1; while (x < z) { z = x; x = (y / x + x) / 2; } }
        else if (y != 0) { z = 1; }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }
}
