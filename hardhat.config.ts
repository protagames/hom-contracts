import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import { Wallet } from "ethers";
import { resolve } from "path";
import { HardhatNetworkUserConfig } from "hardhat/types/config";

dotenv.config({ path: resolve(__dirname, "./.env") });

let mnemonic = process.env.MNEMONIC || "";
const privatekey = process.env.PRIVATEKEY || "";

let wallet;

if (mnemonic) {
  wallet = Wallet.fromMnemonic(mnemonic);
} else if (privatekey) {
  wallet = new Wallet(privatekey);
} else {
  console.warn(
    "Please set MNEMONIC or PRIVATEKEY in a .env file. I create one random seed here for you"
  );
  mnemonic = Wallet.createRandom().mnemonic.phrase;
  console.warn("RANDOM MNEMONIC used: " + mnemonic);
  wallet = Wallet.fromMnemonic(mnemonic);
}

console.log("Using wallet with address: " + wallet.address);

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
function getForkingSettings() {
  const url = process.env.CHAINSTACK_PROVIDER;

  let ret;

  if (url == null) {
    console.warn(
      "........................................................................"
    );
    console.warn(
      "you need to set CHAINSTACK_PROVIDER to fork the chain and test properly."
    );
    console.warn(
      "........................................................................"
    );
    ret = { accounts: { mnemonic } };
  } else {
    ret = {
      accounts: { mnemonic },
      forking: { url },
    };
  }
  // ret.mining = {
  //   auto: false,
  //   interval: [3000, 6000],
  // };
  return ret;
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.9",
    settings: {
      metadata: {
        bytecodeHash: "none",
      },
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
  networks: {
    local: {
      url: "http://localhost:8545",
      accounts: mnemonic ? { mnemonic } : [privatekey],
    },
    bsctest: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: mnemonic ? { mnemonic } : [privatekey],
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: mnemonic ? { mnemonic } : [privatekey],
    },
    hardhat: getForkingSettings(),
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
};

export default config;
