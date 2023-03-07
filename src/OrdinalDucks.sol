// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";

// TODO: Distribution
// Auction is 29 Grailed
// Zodomo is 1 Grailed
// Mods + zodomo are 5 from special/public
// Public is 115

// 30 Grailed
// 22 Special
// 98 Standard
// 150 Total

/// @title An ERC721 contract that mints placeholder NFTs that a recipient can burn alongside providing a Bitcoin address for the team to manually send their ordinal to.
/// @author Zodomo
/// @notice This contract is designed with the idea in mind that the team would be manually managing sending ordinals to their recipients as to avoid using complicated technologies like the Emblem Vaults.
contract OrdinalDucks is ERC721, Ownable2Step, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                EVENTS & ERRORS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    event Whitelist(address indexed _address, uint256 indexed _tier, bool indexed _bool);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    uint256 public nftCount = 0;
    uint256 public wlTimestamp;
    mapping(uint256 => mapping(address => bool)) public whitelist;
    mapping(address => bool) public isWhitelisted;
    string public baseURI;

    mapping(uint256 => address) private _burner;
    mapping(uint256 => string) private _burnAddress;
    address private _auctionWallet = 0xdC25314F47b6F11728Baf41C8f3Fa0cD3f4D9E01;
    address private constant _zodomoWallet = 0xA779fC675Db318dab004Ab8D538CB320D0013F42;
    bytes1[4] private taprootPrefix = [bytes1('b'),bytes1('c'),bytes1('1'),bytes1('p')];

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Confirm the msg.sender has mint privileges
    modifier mintable() {
        require(nftCount < 151, "NFT supply cap reached!");
        require(wlTimestamp > 0, "Whitelist not initiated!");
        require(block.timestamp >= wlTimestamp, "Whitelist timestamp not reached!");
        if (whitelist[0][msg.sender]) { _; } // Auction WL mints
        else if (whitelist[1][msg.sender]) { _; } // One WL mint
        else if (whitelist[2][msg.sender]) { _; } // Two WL mints
        else if (whitelist[3][msg.sender] && block.timestamp >= wlTimestamp + 60 minutes) { _; } // Waddler WL
        else if (block.timestamp >= (wlTimestamp + 105 minutes)) { _; } // Decoy WL / General Mint
        else { revert("Mint conditions are not met!"); }
    }

    // Impose mint limit based on WL tier
    modifier mintLimit() {
        if (whitelist[0][msg.sender] && balanceOf(msg.sender) < 30) { _; }
        else if (whitelist[2][msg.sender] && balanceOf(msg.sender) < 2) { _; }
        else if ((whitelist[1][msg.sender] || whitelist[3][msg.sender]) && balanceOf(msg.sender) < 1) { _; }
        else if (block.timestamp >= (wlTimestamp + 105 minutes) && balanceOf(msg.sender) < 1) { _; }
        else { revert("Mint limitation hit!"); }
    }

    // Confirm the msg.sender either owns the _tokenId NFT or previously burned it
    modifier tokenHolder(uint256 _tokenId) {
        if (ownerOf(_tokenId) == msg.sender || _burner[_tokenId] == msg.sender) { _; }
        else { revert("You do not own this token!"); }
    }

    // Confirm the msg.sender is the auction wallet
    modifier auctioneer() {
        require(msg.sender == _auctionWallet, "Only auction wallet can call this function!");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() ERC721("Ordinal Ducks", "ORDINALDUCKS") payable { }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                LIBRARY
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // TODO: Verify more than just the prefix
    // Confirm the supplied Bitcoin address is the taproot version
    function checkTaprootAddress(string memory _btcAddress) public view returns (bool) {
        bytes memory btcAddress = bytes(_btcAddress);
        for (uint256 i; i < 4;) {
            if (btcAddress[i] != taprootPrefix[i]) {
                revert("BTC address is not a Taproot address!");
            }
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // _baseURI() override to load from storage
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // Swap out auction wallet address
    function _changeAuctionWallet(address _address) internal {
        require(_auctionWallet != _address, "Address is already auction wallet!");
        whitelist[0][_auctionWallet] = false;
        emit Whitelist(_auctionWallet, 0, false);
        _auctionWallet = _address;
        whitelist[0][_auctionWallet] = true;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                RESTRICTED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Change base URI
    function changeBaseURI_(string memory _newBaseURI) public onlyOwner {
        require(bytes(_newBaseURI).length > 0, "New baseURI missing!");
        baseURI = _newBaseURI;
    }

    // Change whitelist timestamp
    function setWLTimestamp_(uint256 _timestamp) public onlyOwner {
        require(_timestamp > block.timestamp, "Timestamp not in future!");
        wlTimestamp = _timestamp;
    }

    // Assign an address to a specific whitelist tier
    // Calling on an address a second time will remove whitelist
    function whitelistAddress_(address _address, uint256 _tier) public onlyOwner {
        // Retrieve current whitelist status
        bool wlStatus = whitelist[_tier][_address];
        // If tier 0 (auction) is set, change auction address
        if (_tier == 0) {
            _changeAuctionWallet(_address);
        }
        // For all other tiers, either set or remove whitelist
        else if (_tier > 0 && _tier < 4) {
            // If not whitelisted for this tier, proceed
            if (!wlStatus) {
                // Confirm address is not in any other whitelist tier
                require(!isWhitelisted[_address], "Address already whitelisted!");
                // Set whitelist tier and whitelist status
                whitelist[_tier][_address] = !wlStatus;
                isWhitelisted[_address] = !wlStatus;
            }
            // If address is in this whitelist tier, remove whitelist and whitelist status
            else {
                whitelist[_tier][_address] = !wlStatus;
                isWhitelisted[_address] = !wlStatus;
            }
        }
        else {
            revert("Invalid WL tier!");
        }
        // Emit event detailing whitelist tier and change of whitelist status
        emit Whitelist(_address, _tier, !wlStatus);
    }

    // Handle auction wallet batch mint
    function auctionBatchMint_() public mintable mintLimit auctioneer {
        uint256 auctioneerBalance = balanceOf(_auctionWallet);
        for (uint256 i; i < 30 - auctioneerBalance;) {
            safeMint();
            unchecked { ++i; }
        }
    }

    // Retrieve burner's Bitcoin address to receive their respective inscription
    function getBurnAddress_(uint256 _tokenId) public view onlyOwner returns (string memory) {
        return _burnAddress[_tokenId];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Safely (ensure recipient can receive ERC721 tokens) mint NFT token
    function safeMint() public mintable mintLimit nonReentrant {
        ++nftCount;
        _safeMint(msg.sender, nftCount);
    }

    // Burn _tokenId NFT in exchange for Bitcoin address
    function burn(uint256 _tokenId, string memory _btcAddress) public tokenHolder(_tokenId) {
        checkTaprootAddress(_btcAddress);
        if (ownerOf(_tokenId) == msg.sender) {
            _burn(_tokenId);
            _burner[_tokenId] == msg.sender;
            _burnAddress[_tokenId] = _btcAddress;
        }
        else {
            _burnAddress[_tokenId] = _btcAddress;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MISCELLANEOUS FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_tokenId > 0 && _tokenId <= 151, "Token ID is out of range!");
        return super.tokenURI(_tokenId);
    }
}