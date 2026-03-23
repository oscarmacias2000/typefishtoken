import hre from "hardhat";

const [deployer] = await hre.ethers.getSigners();
const balance = await hre.ethers.provider.getBalance(deployer.address);
console.log("Wallet:", deployer.address);
console.log("Balance:", hre.ethers.formatEther(balance), "POL");
