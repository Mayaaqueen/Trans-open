# TRANS ON BASE

Smart contracts of Trans v1.0.0

Trans is an autonomous agent for deploying tokens. Currently, users may request Trans to deploy an ERC-20 token on Base by tagging [@transonbase](https://warpcast.com/transonbase) on Farcaster, on our website [transautobot.fun](https://www.transautobot.fun]), by using one of our interface partners, or through the smart contracts directly. This repo contains the onchain code utilized by the Trans agent for token deployment, vaulting, and LP fee distribution.

Documentation for the v1.0.0 


## Fee structure and rewards
As Trans deploys tokens, it initiates 1% fee Uniswap V3 pools on Base. As each token is traded, 1% of each swap in this pool is collected and is assigned as a reward:

- 20% of swap fees - Trans Team
- 80% of fees split between creator and interface (immutable after token deployment)

## Deployed Contracts


### v1.0.0
Base Mainnet:
- Trans Factory (v1.0.0): [0x4b04698671037a41244ceDf287DDd3C19006848d](https://basescan.org/address/0x4b04698671037a41244ceDf287DDd3C19006848d)
- LpLockerv2 (v1.0.0): [0x69068cCdB3fa76ae6A535E363120A4502EF27315](https://basescan.org/address/0x69068cCdB3fa76ae6A535E363120A4502EF27315)
- TransVault (v1.0.0): [0x66eeEAf7fDb980AfF3bd2d27e67305202157B93B](https://basescan.org/address/)

### v1.0.0 (Base Sepolia)
- Trans Factory (v1.0.0): [0x7aF66ac7518785D9A550F0c89000ABC7d442caB4](https://sepolia.basescan.org/address/0x7aF66ac7518785D9A550F0c89000ABC7d442caB4)
- LpLockerv2 (v1.0.0): [0xD505564E46365A7Be92957a1fF3D8C259f1ED3e0](https://sepolia.basescan.org/address/0xD505564E46365A7Be92957a1fF3D8C259f1ED3e0)
- TransVault (v1.0.0): [0x69068cCdB3fa76ae6A535E363120A4502EF27315](https://sepolia.basescan.org/address/0x69068cCdB3fa76ae6A535E363120A4502EF27315)

If you'd like these contracts on another chain, [please reach out to us](support@transautbot.fun)! For superchain purposes, we need to ensure that the Trans contracts have the same address.


## Usage

Token deployers should use the `Trans::deployToken()` function to deploy tokens.

Note that the follow parameters are needed for deployment:
```solidity
/**
 * Configuration settings for token creation
 */

struct RewardsConfig {
    uint256 creatorReward;
    address creatorAdmin;
    address creatorRewardRecipient;
    address interfaceAdmin;
    address interfaceRewardRecipient;
}

struct TokenConfig {
    string name;
    string symbol;
    bytes32 salt;
    string image;
    string metadata;
    string context;
    uint256 originatingChainId;
}

struct VaultConfig {
    uint8 vaultPercentage;
    uint256 vaultDuration;
}

struct PoolConfig {
    address pairedToken;
    int24 tickIfToken0IsNewToken;
}

struct InitialBuyConfig {
    uint24 pairedTokenPoolFee;
    uint256 pairedTokenSwapAmountOutMinimum;
}

struct DeploymentConfig {
    TokenConfig tokenConfig;
    VaultConfig vaultConfig;
    PoolConfig poolConfig;
    InitialBuyConfig initialBuyConfig;
    RewardsConfig rewardsConfig;
}

function deployToken(DeploymentConfig tokenConfig) external payable {...}
```

