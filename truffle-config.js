/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * trufflesuite.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */
require('dotenv-flow').config({
    path: 'envs/',
    node_env: process.env.NODE_ENV || 'test'
});

console.log("env:", process.env.NODE_ENV);

const HDWalletProvider = require('@truffle/hdwallet-provider');
const mnemonic = process.env.DEPLOYER_PRIVATE_KEY;

module.exports = {

    networks: {
        testnet: {
            provider: () => new HDWalletProvider(mnemonic, 'https://data-seed-prebsc-2-s3.binance.org:8545/'),
            network_id: 97
        },
        mainnet: {
            provider: () => new HDWalletProvider(mnemonic, 'https://bsc-dataseed1.binance.org/'),
            network_id: 56
        }
    },

    // Set default mocha options here, use special reporters etc.
    mocha: {
        // timeout: 100000
    },

    // Configure your compilers
    compilers: {
        solc: {
            version: "^0.6.0",    // Fetch exact version from solc-bin (default: truffle's version)
            docker: false,        // Use "0.5.1" you've installed locally with docker (default: false)
            settings: {          // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 200
                },
                evmVersion: "istanbul"
            }
        }
    }
};
