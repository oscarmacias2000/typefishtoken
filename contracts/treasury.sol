// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    function sendReward(address to, uint256 amount) external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Treasury {
    address public owner;
    IERC20 public token;
    address public stakingContract;

    modifier onlyOwner() {
        require(msg.sender == owner, "No autorizado");
        _;
    }

    modifier onlyStaking() {
        require(msg.sender == stakingContract, "Solo staking");
        _;
    }

    constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    function setStaking(address _staking) external onlyOwner {
        stakingContract = _staking;
    }

    function enviarReward(address to, uint256 amount) external onlyStaking {
        require(token.balanceOf(address(this)) >= amount, "Sin fondos");
        token.transfer(to, amount);
    }
}