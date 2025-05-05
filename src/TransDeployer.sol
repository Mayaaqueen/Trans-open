// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TransToken} from "./TransToken.sol";
import {ITrans} from "./interfaces/ITrans.sol";

/// @notice Trans Token Launcher
library TransDeployer {
    function deployToken(ITrans.TokenConfig memory tokenConfig, address admin, uint256 supply)
        external
        returns (address tokenAddress)
    {
        TransToken token = new TransToken{salt: keccak256(abi.encode(admin, tokenConfig.salt))}(
            tokenConfig.name,
            tokenConfig.symbol,
            supply,
            admin,
            tokenConfig.image,
            tokenConfig.metadata,
            tokenConfig.context,
            tokenConfig.originatingChainId
        );
        tokenAddress = address(token);
    }
}
