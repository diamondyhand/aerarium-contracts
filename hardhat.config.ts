// import "./task";
import { HardhatUserConfig } from "hardhat/config";
// import "@openzeppelin/hardhat-upgrades";
// import "@nomiclabs/hardhat-etherscan";
// import "@nomiclabs/hardhat-waffle";
// import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";

// import "hardhat-gas-reporter";
// import "hardhat-interface-generator";
// import "solidity-coverage";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
    //   loggingEnabled: false,
      forking: {
        // Arbi
        url: "https://rpc.radiant.capital/70ff72eec58b50f824282a0c28f3434d585c9410/",
        blockNumber: 59175778,
      },
    },
    localhost: {
      timeout: 120000,
    },
  },
  mocha: {
    timeout: 1000000000,
    bail: true
  },
};

// if (process.env.IS_CI === "true") {
//   if (config && config !== undefined) {
//     if (config.hasOwnProperty("mocha") && config.mocha !== undefined) {
//       config.mocha.reporter = "json";
//       config.mocha.reporterOptions = {
//         output: "test-results.json",
//       };
//     }
//   }
// }

export default config;
