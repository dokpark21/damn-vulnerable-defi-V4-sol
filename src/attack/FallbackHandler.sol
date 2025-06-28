// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FallbackHandler {
    function approveToken(address _token, address _to) public {
        IERC20(_token).approve(_to, 10e18);
    }
}
