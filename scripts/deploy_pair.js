// scripts/deploy_pair.js
import hre from "hardhat";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Desplegando con:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "POL");

  // ── Direcciones ──
  // TFISH en Polygon local
  const TFISH_ADDRESS   = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  // BNB bridgeado en Polygon (dirección real en mainnet)
  // En testnet desplegamos un mock BNB
  const TREASURY        = deployer.address;

  console.log("\n[1/3] Desplegando Mock BNB (solo para testnet)...");
  const MockBNB = await hre.ethers.getContractFactory("MockERC20");
  // Si no tienes MockERC20, usamos el token TFISH como placeholder
  // En mainnet usar: 0xecdCb5B88F0BF0Fd2adf9C87f9d16A1f21668d5 (BNB en Polygon)
  
  console.log("[2/3] Desplegando TFISHBNBPair...");
  const Pair = await hre.ethers.getContractFactory("TFISHBNBPair");
  const pair = await Pair.deploy(
    TFISH_ADDRESS,
    TFISH_ADDRESS, // placeholder — cambiar por BNB real en mainnet
    TREASURY
  );
  await pair.waitForDeployment();
  const pairAddr = await pair.getAddress();
  console.log("✅ TFISHBNBPair:", pairAddr);

  console.log("\n[3/3] Configurando liquidez inicial...");
  const tfish = await hre.ethers.getContractAt("IERC20", TFISH_ADDRESS);
  
  // Aprobar tokens para el par
  const initTFISH = hre.ethers.parseEther("10000");  // 10,000 TFISH
  const initBNB   = hre.ethers.parseEther("5");      // 5 BNB equivalente

  await tfish.approve(pairAddr, initTFISH * 2n);
  console.log("✅ Aprobación de TFISH completada");

  // Agregar liquidez inicial
  await pair.addLiquidity(initTFISH, initBNB, 0, 0);
  console.log("✅ Liquidez inicial agregada");

  // Fondear recompensas de staking
  await pair.fundRewards(hre.ethers.parseEther("50000"));
  console.log("✅ Pool de recompensas fondeado: 50,000 TFISH");

  // Stats del pool
  const stats = await pair.getPoolStats();
  const price = await pair.getPrice();

  console.log("\n════════════════════════════════════════");
  console.log("TFISH/BNB PAIR — RESUMEN DEL DEPLOY");
  console.log("════════════════════════════════════════");
  console.log("Contrato par:     ", pairAddr);
  console.log("TFISH en pool:    ", hre.ethers.formatEther(stats[0]));
  console.log("BNB en pool:      ", hre.ethers.formatEther(stats[1]));
  console.log("LP tokens totales:", hre.ethers.formatEther(stats[2]));
  console.log("Precio TFISH/BNB: ", hre.ethers.formatEther(price[0]));
  console.log("Fee de swap:       0.30%");
  console.log("Fee protocolo:     0.05%");
  console.log("Fee LP:            0.25%");
  console.log("\n🌐 BNB real en Polygon mainnet:");
  console.log("   0xecdCb5B88F0BF0Fd2adf9C87f9d16A1f21668d5");
  console.log("════════════════════════════════════════");
}

main().catch(console.error);
