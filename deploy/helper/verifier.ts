import hre from "hardhat";
import polygonMumbaiAddresses from "../addresses/polygonMumbai.json";
import scrollAlphaAddresses from "../addresses/scrollAlpha.json";

async function verify(address: string, constructorArguments?: any) {
    await hre.run("verify:verify", {
        address,
        constructorArguments,
    });
}

async function main() {
    const [signer] = await ethers.getSigners();
    const network = await signer.provider?.getNetwork();

    switch (network?.chainId) {
        case 80001: {
            await verify(polygonMumbaiAddresses.compatibilityFallbackHandler);
            await verify(polygonMumbaiAddresses.ecdsaOmniValidator);
            await verify(polygonMumbaiAddresses.versaOmniSingleton, [
                polygonMumbaiAddresses.entryPoint,
                polygonMumbaiAddresses.lzEndpoint,
            ]);
            await verify(polygonMumbaiAddresses.versaOmniFactory, [
                polygonMumbaiAddresses.versaOmniSingleton,
                polygonMumbaiAddresses.compatibilityFallbackHandler,
                polygonMumbaiAddresses.lzEndpoint,
                [80001, 534353],
                [10109, 10170],
            ]);
            break;
        }
        case 534353: {
            console.log("unsupported network");
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
