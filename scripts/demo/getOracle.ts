import hre, { ethers } from "hardhat";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollAlphaAddresses from "../../deploy/addresses/scrollAlpha.json";

async function main() {
    let [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    let contractAddress, dstChainId;
    switch (chainId) {
        case 80001: {
            contractAddress = polygonMumbaiAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["scroll-alpha"];
            break;
        }
        case 534353: {
            contractAddress = scrollAlphaAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["polygon-mumbai"];
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const contractInstance = await ethers.getContractAt("VersaOmniFactory", contractAddress);
    console.log(`[${hre.network.name}] VersaOmniFactory Address: ${contractAddress}`);
    const data = await contractInstance.getOracle(dstChainId);
    console.log(`✅ Get Oracle: src (${chainId}) -> dst (${dstChainId}): ${data}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
