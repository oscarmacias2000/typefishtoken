# MTK Token Project — Guía completa de deploy

## 🗂 Estructura del proyecto
```
token-project/
├── contracts/
│   ├── MiToken.sol      # ERC-20 con tax del 1%
│   └── MiStaking.sol    # Staking con lock period y recompensas
├── scripts/
│   └── deploy.js        # Deploy automático de ambos contratos
├── frontend/
│   └── index.html       # dApp lista para conectar MetaMask
├── hardhat.config.js
├── package.json
└── .env.example
```

## 🚀 Setup paso a paso

### Paso 1 — Instalar dependencias
```bash
npm install
```

### Paso 2 — Configurar variables de entorno
```bash
cp .env.example .env
# Edita .env y agrega tu PRIVATE_KEY y POLYGONSCAN_API_KEY
```

⚠️ **NUNCA subas tu .env a GitHub**. Agrega `.env` a tu `.gitignore`.

### Paso 3 — Compilar contratos
```bash
npm run compile
```
Debes ver: `Compilation finished successfully`

### Paso 4 — Deploy en testnet (GRATIS)
Primero necesitas MATIC de testnet:
1. Ve a https://faucet.polygon.technology/
2. Conecta tu wallet y solicita POL (Mumbai testnet)
3. Espera 1-2 minutos

```bash
npm run deploy:testnet
```

Guarda las direcciones que imprime el script.

### Paso 5 — Probar en la dApp
- Abre `frontend/index.html` en tu navegador
- Conecta MetaMask (asegúrate de estar en Mumbai testnet)
- Reemplaza las direcciones de contratos en el JS de la dApp

### Paso 6 — Deploy en mainnet
Cuando todo funcione en testnet:
```bash
npm run deploy:mainnet
```
Costo estimado: ~$2-5 USD en MATIC

---

## 💰 Estrategia para generar $1,000 MXN/día (~$50 USD)

### Fuente 1: Tax del token (1%)
- Necesitas ~$5,000 USD de volumen diario
- Con una comunidad de 100-200 holders activos es alcanzable
- El tax va directo a tu wallet

### Fuente 2: Liquidez en QuickSwap
- Deposita $30-50 USD en el par MTK/MATIC
- Ganas 0.3% de cada swap
- Con $17,000 USD de volumen diario → $50 USD/día

### Fuente 3: Holders en staking
- El staking reduce el supply circulante
- Menos supply = más demanda = precio sube
- Precio más alto = más volumen = más tax

### Timeline realista
| Semana | Objetivo |
|--------|----------|
| 1 | Deploy en testnet, pruebas |
| 2 | Deploy mainnet, dApp online |
| 3 | Liquidez inicial en QuickSwap, primeros holders |
| 4 | Marketing (Twitter, Telegram, Reddit) |
| 5-8 | Crecer comunidad a 100+ holders |
| 2-3 meses | Alcanzar $1,000 MXN/día consistentes |

---

## 🔗 Recursos importantes
- Faucet Mumbai: https://faucet.polygon.technology/
- PolygonScan: https://polygonscan.com/
- QuickSwap: https://quickswap.exchange/
- OpenZeppelin Docs: https://docs.openzeppelin.com/contracts/5.x/

## ⚠️ Aviso importante
Este proyecto es con fines educativos. Investiga las regulaciones de tu país 
antes de lanzar un token. El éxito depende de construir una comunidad real.
