// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TypeFishToken is ERC20, Ownable {

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public taxBasisPoints         = 100;           // 1%
    uint256 public constant MAX_TAX_BP    = 500;           // máx 5%
    address public treasury;

    mapping(address => bool) public isExempt;

    event TaxCollected(address indexed from, address indexed to, uint256 taxAmount);
    event ExemptUpdated(address indexed account, bool exempt);
    event TaxUpdated(uint256 newBasisPoints);
    event TreasuryUpdated(address newTreasury);

    constructor(address _treasury, uint256 initialSupply) ERC20("TypeFish Token", "TFISH") Ownable(msg.sender) {
        require(_treasury != address(0), "Treasury invalido");
        treasury = _treasury;
        isExempt[msg.sender] = true;
        isExempt[_treasury]  = true;
        _mint(msg.sender, initialSupply);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0) || isExempt[from] || isExempt[to]) {
            super._update(from, to, amount);
            return;
        }
        uint256 taxAmount      = (amount * taxBasisPoints) / 10_000;
        uint256 transferAmount = amount - taxAmount;
        if (taxAmount > 0) {
            super._update(from, treasury, taxAmount);
            emit TaxCollected(from, to, taxAmount);
        }
        super._update(from, to, transferAmount);
    }

    function setExempt(address account, bool exempt) external onlyOwner {
        isExempt[account] = exempt;
        emit ExemptUpdated(account, exempt);
    }

    function setTax(uint256 newBasisPoints) external onlyOwner {
        require(newBasisPoints <= MAX_TAX_BP, "Tax demasiado alto");
        taxBasisPoints = newBasisPoints;
        emit TaxUpdated(newBasisPoints);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalido");
        isExempt[treasury]    = false;
        treasury              = newTreasury;
        isExempt[newTreasury] = true;
        emit TreasuryUpdated(newTreasury);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function calculateTax(uint256 amount) external view returns (uint256) {
        return (amount * taxBasisPoints) / 10_000;
    }
}
