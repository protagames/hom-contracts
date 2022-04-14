import { BigNumber } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Artifact } from "hardhat/types";
import axios from "axios";

export function expandTo18Decimals(n: number): BigNumber {
  return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18));
}

export function expandTo9Decimals(value: string): BigNumber {
  return ethers.utils.parseUnits(value, "9");
}

export function bigNumberToFloat(n: BigNumber): number {
  return parseFloat(ethers.utils.formatEther(n));
}
export function daysToUnixDate(days: number): number {
  return days * 24 * 60 * 60;
}
export function range(start: number, end: number): number[] {
  return Array(end - start + 1)
    .fill(0)
    .map((_, idx) => start + idx);
}
