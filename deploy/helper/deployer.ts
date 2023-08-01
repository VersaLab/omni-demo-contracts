import { ethers } from "hardhat";

export async function deployCompatibilityFallbackHandler() {
    const CompatibilityFallbackHandler = await ethers.getContractFactory("CompatibilityFallbackHandler");
    const compatibilityFallbackHandler = await CompatibilityFallbackHandler.deploy();
    console.log("CompatibilityFallbackHandler deployed to: ", compatibilityFallbackHandler.address);
    return compatibilityFallbackHandler;
}

export async function deployECDSAOmniValidator() {
    const ECDSAOmniValidator = await ethers.getContractFactory("ECDSAOmniValidator");
    const ecdsaOmniValidator = await ECDSAOmniValidator.deploy();
    console.log("ECDSAOmniValidator deployed to: ", ecdsaOmniValidator.address);
    return ecdsaOmniValidator;
}

export interface VersaOmniSingletonData {
    entryPoint: string;
    lzEndpoint: string;
}

export async function deployVersaOmniSingleton(data: VersaOmniSingletonData) {
    const VersaOmniSingleton = await ethers.getContractFactory("VersaOmniWallet");
    const versaOmniSingleton = await VersaOmniSingleton.deploy(data.entryPoint, data.lzEndpoint);
    await versaOmniSingleton.deployed();
    console.log("VersaOmniSingleton deployed to:", versaOmniSingleton.address);
    return versaOmniSingleton;
}

export interface VersaOmniFactoryData {
    versaOmniSingleton: string;
    fallbackHandler: string;
    lzEndpoint: string;
    supportedChainIds: number[];
    supportedLzChainIds: number[];
}

export async function deployVersaOmniFactory(data: VersaOmniFactoryData) {
    const VersaOmniFactory = await ethers.getContractFactory("VersaOmniFactory");
    console.log(data);
    const versaOmniFactory = await VersaOmniFactory.deploy(
        data.versaOmniSingleton,
        data.fallbackHandler,
        data.lzEndpoint,
        data.supportedChainIds,
        data.supportedLzChainIds
    );
    await versaOmniFactory.deployed();
    console.log("VersaOmniFactory deployed to:", versaOmniFactory.address);
    return versaOmniFactory;
}
