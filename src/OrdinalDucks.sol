// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";

// TODO: Implement mint costs

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

    uint256 public immutable maxSupply;
    uint256 public wlTimestamp;
    mapping(uint256 => mapping(address => bool)) public whitelist;
    mapping(address => bool) public isWhitelisted;
    string public baseURI;
    
    uint256 private _nftCount = 0;
    bool private _auctionMinted;
    bool private _devMinted;
    mapping(uint256 => address) private _burner;
    mapping(uint256 => string) private _burnAddress;
    address private _auctionWallet;
    address private _devWallet;
    bytes1[4] private taprootPrefix = [bytes1('b'),bytes1('c'),bytes1('1'),bytes1('p')];

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Confirm the msg.sender has mint privileges
    modifier mintable() {
        require(_nftCount < maxSupply, "NFT supply cap reached!");
        require(wlTimestamp > 0, "Whitelist not initiated!");
        require(block.timestamp >= wlTimestamp, "Whitelist timestamp not reached!");
        if (whitelist[0][msg.sender]) { _; } // Auction WL mints
        else if (whitelist[1][msg.sender]) { _; } // One WL mint
        else if (whitelist[2][msg.sender]) { _; } // Dev / Top D's 2 WL mints
        else if (whitelist[3][msg.sender] && block.timestamp >= wlTimestamp + 60 minutes) { _; } // Waddler WL
        else if (block.timestamp >= (wlTimestamp + 105 minutes)) { _; } // Decoy / General Mint
        else { revert("Mint conditions are not met!"); }
    }

    // Impose mint limit based on WL tier
    modifier mintLimit() {
        if (whitelist[0][msg.sender] && balanceOf(msg.sender) < 30) { _; } // Auction wallet
        else if (whitelist[2][msg.sender] && balanceOf(msg.sender) < 2) { _; } // Dev + Top D's
        else if ((whitelist[1][msg.sender] || whitelist[3][msg.sender]) && balanceOf(msg.sender) < 1) { _; } // One WL / Waddlers
        else if (block.timestamp >= (wlTimestamp + 105 minutes) && balanceOf(msg.sender) < 1) { _; } // Everyone else after whitelist
        else { revert("Mint limitation hit!"); }
    }

    // Require mint is complete
    modifier mintComplete() {
        require(currentSupply() == maxSupply, "Mint cap not reached!");
        _;
    }

    // Confirm the msg.sender either owns the _tokenId NFT or previously burned it
    modifier tokenHolder(uint256 _tokenId) {
        if (ownerOf(_tokenId) == msg.sender || _burner[_tokenId] == msg.sender) { _; }
        else { revert("You do not own this token!"); }
    }

    // Confirm the msg.sender is the auction wallet
    modifier auctioneer() {
        require(msg.sender == _auctionWallet, "Only auction wallet can call this function!");
        require(_devMinted, "Dev hasn't minted yet!");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(address _auction, address _dev, string memory _uri) ERC721("Ordinal Ducks", "ORDINALDUCKS") payable {
        maxSupply = 150;
        whitelist[0][_auction] = true;
        whitelist[2][_dev] = true;
        _auctionWallet = _auction;
        _devWallet = _dev;
        baseURI = _uri;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                LIBRARY
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Confirm the supplied Bitcoin address is the taproot version
    function checkTaprootAddress(string memory _btcAddress) public view returns (bool) {
        bytes memory btcAddress = bytes(_btcAddress);
        for (uint256 i; i < 4;) {
            if (btcAddress[i] != taprootPrefix[i]) {
                revert("BTC address is not a Taproot address!");
            }
            unchecked { ++i; }
        }
        return true;
    }

    // Return current supply
    function currentSupply() public view returns (uint256) {
        uint256 supply = _nftCount;
        if (_auctionMinted) { supply += 29; }
        if (_devMinted) { supply += 1; }
        return supply;
    }

    // Concatenate two strings for tokenURI
    function concatenate(string memory _str1, string memory _str2) public pure returns (string memory) {
        bytes memory strBytes1 = bytes(_str1);
        bytes memory strBytes2 = bytes(_str2);
        bytes memory combinedBytes = new bytes(strBytes1.length + strBytes2.length);
        for (uint i = 0; i < strBytes1.length; i++) {
            combinedBytes[i] = strBytes1[i];
        }
        for (uint j = 0; j < strBytes2.length; j++) {
            combinedBytes[strBytes1.length + j] = strBytes2[j];
        }
        return string(combinedBytes);
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

    // Handle auction wallet batch mint
    function _auctionBatchMint() internal auctioneer {
        for (uint256 i = 121; i <= maxSupply;) {
            if (ownerOf(i) == _devWallet) { continue; }
            _safeMint(_auctionWallet, i);
            unchecked { ++i; }
        }
        _auctionMinted = true;
    }

    // Randomize token ID, attempt 10 runs before locating available ID
    function _randomId() internal view returns (uint256) {
        uint256 index;
        for (uint256 i; i < 10;) {
            index = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, i))) % (121);
            if (ownerOf(index) == address(0) && index > 0) {
                return index;
            }
            unchecked { ++i; }
        }
        for (uint256 i = 1; i <= 120;) {
            if (ownerOf(i) == address(0)) {
                return i;
            }
            unchecked { ++i; }
        }
        return 0;
    }

    // Process mint logic/distribution for different whitelist tiers
    function _mintRouter() internal {
        // If auction wallet is msg.sender, process auction mint logic
        if (whitelist[0][msg.sender]) {
            _auctionBatchMint();
        }
        // Allocate one randomized grailed mint to dev
        else if (msg.sender == _devWallet && balanceOf(_devWallet) < 1) {
            _safeMint(_devWallet, 121 + (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % 30));
            _devMinted = true;
            ++_nftCount;
        }
        // Process mints for everyone else
        // Restrictions are pre-imposed before the mint routing logic
        else {
            _safeMint(msg.sender, _randomId());
            ++_nftCount;
        }
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

    // Retrieve burner's Bitcoin address to receive their respective inscription
    function getBurnAddress_(uint256 _tokenId) public view onlyOwner returns (string memory) {
        return _burnAddress[_tokenId];
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Safely (ensure recipient can receive ERC721 tokens) mint NFT token
    function safeMint() public mintable mintLimit nonReentrant payable {
        _mintRouter();
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
        require(_tokenId > 0 && _tokenId <= maxSupply, "Token ID is out of range!");
        return concatenate(super.tokenURI(_tokenId), ".png");
    }
}