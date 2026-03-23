// scripts/deploy.js
import hre from "hardhat";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Desplegando con cuenta:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "MATIC");

  // ── 1. Deploy del Token ────────────────────────────────────
  // El treasury es tu propia wallet (recibe el 1% de tax)
  const treasury = deployer.address; // puedes cambiar esto por otra wallet

  const Token = await hre.ethers.getContractFactory("TypeFishToken");
  const token = await Token.deploy(treasury);
  await token.waitForDeployment();
  console.log("✅ TypeFishToken desplegado en:", await token.getAddress());

  // ── 2. Deploy del Staking ──────────────────────────────────
  const Staking = await hre.ethers.getContractFactory("MiStaking");
  const staking = await Staking.deploy(await token.getAddress(), treasury);
  await staking.waitForDeployment();
  console.log("✅ MiStaking desplegado en:", await staking.getAddress());

  // ── 3. Config post-deploy ──────────────────────────────────
  // Eximir al contrato de staking del tax
  const tx1 = await token.setExempt(await staking.getAddress(), true);
  await tx1.wait();
  console.log("✅ Staking exento de tax");

  // Fondear el staking con 50,000 tokens para recompensas (5% del supply)
  const fundAmount = hre.ethers.parseEther("50000");
  const tx2 = await token.approve(await staking.getAddress(), fundAmount);
  await tx2.wait();
  const tx3 = await staking.fundRewards(fundAmount);
  await tx3.wait();
  console.log("✅ Staking fondeado con 50,000 TFISH para recompensas");

  // ── 4. Resumen final ───────────────────────────────────────
  console.log("\n════════════════════════════════════");
  console.log("  RESUMEN DEL DEPLOY");
  console.log("════════════════════════════════════");
  console.log("  Token (TFISH):", await token.getAddress());
  console.log("  Staking:    ", await staking.getAddress());
  console.log("  Treasury:   ", treasury);
  console.log("  Supply:      1,000,000 TFISH");
  console.log("  Tax:         1%");
  console.log("  Lock period: 7 días");
  console.log("════════════════════════════════════");
  console.log("\nGuarda estas direcciones, las necesitas para la dApp.");

  // ── 5. Verificar en PolygonScan (opcional, necesita API key) ─
  if (process.env.POLYGONSCAN_API_KEY) {
    console.log("\nVerificando en PolygonScan...");
    await hre.run("verify:verify", {
      address: await token.getAddress(),
      constructorArguments: [treasury],
    });
    await hre.run("verify:verify", {
      address: await staking.getAddress(),
      constructorArguments: [await token.getAddress(), treasury],
    });
    console.log("✅ Contratos verificados en PolygonScan");
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
