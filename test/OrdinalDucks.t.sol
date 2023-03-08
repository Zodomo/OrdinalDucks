// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/console.sol";
import "../src/OrdinalDucks.sol";

contract OrdinalDucksLaboratory is DSTestPlus {

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                SETUP
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    OrdinalDucks ordducks;
    address[] addresses = [address(0xABCD), address(0xBEEF), address(0xCECE), address(0xDEED)];

    function setUp() public {
        hevm.warp(1);
        ordducks = new OrdinalDucks(addresses[0], addresses[1], "https://test.com/", 300);
        for (uint i; i < addresses.length; i++) {
            hevm.deal(addresses[i], 100 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                TESTS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    function testConstructor() public view {
        ordducks.currentSupply();
        ordducks.maxSupply();
        ordducks.checkWhitelist(0, addresses[0]);
        ordducks.checkWhitelist(2, addresses[1]);
        ordducks.baseURI();
        ordducks.wlTimestamp();
        console.log(block.timestamp);
    }

    function testCheckTaprootAddress() public {
        ordducks.checkTaprootAddress("bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06e");
        hevm.expectRevert("BTC address is not a Taproot address!");
        ordducks.checkTaprootAddress("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq");
    }

    function testCurrentSupply() public {
        require(ordducks.currentSupply() == 0, "currentSupply()");
        hevm.warp(301);
        ordducks.whitelistAddress_(addresses[2], 2);
        hevm.prank(addresses[2]);
        ordducks.safeMint();
        require(ordducks.currentSupply() == 1, "currentSupply()");
    }

    /*function testConcatenate() public view {
        require(bytes32(keccak256(abi.encodePacked(ordducks.concatenate("test1", "test2")))) == 
            bytes32(keccak256(abi.encodePacked("test1test2"))), "concatenate()");
    }*/

    function testCheckWhitelist() public {
        ordducks.whitelistAddress_(addresses[2], 2);
        require(ordducks.checkWhitelist(2, addresses[2]));
    }

    function testChangeBaseURI() public {
        require(bytes32(keccak256(abi.encodePacked(ordducks.baseURI()))) == 
            bytes32(keccak256(abi.encodePacked("https://test.com/"))), "baseURI()");
        ordducks.changeBaseURI_("https://test2.com/");
        require(bytes32(keccak256(abi.encodePacked(ordducks.baseURI()))) == 
            bytes32(keccak256(abi.encodePacked("https://test2.com/"))), "baseURI()");
    }

    function testSetWLTimestamp() public {
        require(ordducks.wlTimestamp() == 300, "wlTimestamp()");
        ordducks.setWLTimestamp_(500);
        require(ordducks.wlTimestamp() == 500, "wlTimestamp()");
    }

    function testWhitelistAddress() public {
        require(ordducks.checkWhitelist(0, addresses[0]));
        require(ordducks.checkWhitelist(2, addresses[1]));
        ordducks.whitelistAddress_(addresses[2], 1);
        ordducks.whitelistAddress_(addresses[3], 3);
        require(ordducks.checkWhitelist(1, addresses[2]));
        require(ordducks.checkWhitelist(3, addresses[3]));
    }

    function testRemoveWhitelist() public {
        ordducks.whitelistAddress_(addresses[1], 2);
        require(!ordducks.checkWhitelist(2, addresses[1]), "Whitelist not revoked");
    }

    function testWhitelistInvalidTier() public {
        hevm.expectRevert("Invalid WL tier!");
        ordducks.whitelistAddress_(addresses[2], 4);
    }

    function testGetBurnAddress() public {
        hevm.warp(100000);
        hevm.startPrank(addresses[3]);
        uint256 tokenId = ordducks.safeMint();
        ordducks.burn(tokenId, "bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06e");
        hevm.stopPrank();
        require(bytes32(keccak256(abi.encodePacked(ordducks.getBurnAddress_(tokenId)))) == 
            bytes32(keccak256(abi.encodePacked("bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06e"))));
    }

    function testDevMint() public {
        hevm.prank(addresses[1]);
        uint256 tokenId = ordducks.safeMint();
        require(tokenId > 120 && tokenId < 151, "Dev mint range error");
    }

    function testChangeAuctionWallet() public {
        ordducks.whitelistAddress_(addresses[3], 0);
        require(!ordducks.checkWhitelist(0, addresses[0]), "Old auction address still present");
        require(ordducks.checkWhitelist(0, addresses[3]), "New auction address not set");
    }

    function testBurn() public {
        hevm.startPrank(addresses[1]);
        uint256 tokenId = ordducks.safeMint();
        ordducks.burn(tokenId, "bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06e");
    }

    function testReburn() public {
        hevm.startPrank(addresses[1]);
        uint256 tokenId = ordducks.safeMint();
        ordducks.burn(tokenId, "bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06e");
        ordducks.burn(tokenId, "bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06f");
        hevm.stopPrank();
        require(bytes32(keccak256(abi.encodePacked(ordducks.getBurnAddress_(tokenId)))) == 
            bytes32(keccak256(abi.encodePacked("bc1pmzfrwwndsqmk5yh69yjr5lfgfg4ev8c0tsc06f"))));
    }

    function testTokenURI() public {
        hevm.startPrank(addresses[1]);
        uint256 tokenId = ordducks.safeMint();
        require(bytes32(keccak256(abi.encodePacked(ordducks.tokenURI(tokenId)))) == 
            bytes32(keccak256(abi.encodePacked("https://test.com/", Strings.toString(tokenId), ".png"))));
    }

    function testAuctionMint() public {
        hevm.prank(addresses[1]);
        console.log(ordducks.safeMint());
        hevm.prank(addresses[0]);
        console.log(ordducks.safeMint());
        console.log(ordducks.balanceOf(addresses[0]));
        require(ordducks.balanceOf(addresses[0]) == 29, "Auction mint balanceOf()");
    }

    function testMintSimulation() public {
        hevm.startPrank(addresses[1]);
        console.log(ordducks.safeMint());
        console.log(ordducks.safeMint());
        hevm.stopPrank();
        hevm.prank(addresses[0]);
        console.log(ordducks.safeMint());
        for (uint256 i = 1; i <= 4; ++i) {
            hevm.deal(address(uint160(i)), 100 ether);
            ordducks.whitelistAddress_(address(uint160(i)), 1);
            hevm.prank(address(uint160(i)));
            ordducks.safeMint();
        }
        for (uint256 i = 5; i <= 19; ++i) {
            hevm.deal(address(uint160(i)), 100 ether);
            ordducks.whitelistAddress_(address(uint160(i)), 2);
            hevm.startPrank(address(uint160(i)));
            ordducks.safeMint();
            ordducks.safeMint();
            hevm.stopPrank();
        }
        for (uint256 i = 20; i <= 64; i++) {
            hevm.deal(address(uint160(i)), 100 ether);
            ordducks.whitelistAddress_(address(uint160(i)), 1);
            hevm.prank(address(uint160(i)));
            ordducks.safeMint();
        }
        hevm.warp(4000);
        for (uint256 i = 65; i < 105; i++) {
            hevm.deal(address(uint160(i)), 100 ether);
            ordducks.whitelistAddress_(address(uint160(i)), 3);
            hevm.prank(address(uint160(i)));
            ordducks.safeMint();
        }
    }
}