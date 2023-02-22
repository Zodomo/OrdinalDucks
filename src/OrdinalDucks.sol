// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC721/ERC721.sol";

// TODO: Distribution
// Auction is 29 Grailed 
// Zodomo is 1 Grailed
// Mods + zodomo are 5 from special/public
// Public is 115

// TODO: Implement WBTC quoting/swapping

/// @title An ERC721 contract that mints placeholder NFTs that a recipient can burn alongside providing a Bitcoin address for the team to manually send their ordinal to.
/// @author Zodomo
/// @notice This contract is designed with the idea in mind that the team would be manually managing sending ordinals to their recipients as to avoid using complicated technologies like the Emblem Vaults.
contract OrdinalDucks is ERC721, Ownable2Step, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                EVENTS & ERRORS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    uint256 public nftCount = 1;
    uint256 public wlTimestamp;
    mapping(uint256 => mapping(address => bool)) public isWhitelisted;
    string public baseURI;

    mapping(uint256 => address) private _burner;
    mapping(uint256 => string) private _burnAddress;
    address private _auctionWallet;
    address private constant _zodomoWallet = 0xA779fC675Db318dab004Ab8D538CB320D0013F42;
    bytes1[4] private taprootPrefix = [bytes1('b'),bytes1('c'),bytes1('1'),bytes1('p')];

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Confirm the msg.sender has mint privileges
    modifier mintable() {
        require(nftCount < 151, "NFT supply cap reached!");
        require(wlTimestamp > 0, "Whitelist not initiated!");
        if (isWhitelisted[0][msg.sender]) { _; }
        else if (isWhitelisted[1][msg.sender]) { _; }
        else if (isWhitelisted[2][msg.sender] && block.timestamp >= wlTimestamp) { _; }
        else if (isWhitelisted[3][msg.sender] && block.timestamp >= (wlTimestamp + 30 minutes)) { _; }
        else if (isWhitelisted[4][msg.sender] && block.timestamp >= (wlTimestamp + 60 minutes)) { _; }
        else if (block.timestamp >= (wlTimestamp + 90 minutes)) { _; }
        else { revert("Mint conditions are not met!"); }
    }

    // Impose one mint per wallet limit
    // Zodomo's address is the only wallet address than can mint two
    modifier mintLimit() {
        if (msg.sender == _zodomoWallet && balanceOf(msg.sender) < 2) { _; }
        if (msg.sender == _auctionWallet && balanceOf(msg.sender) < 30) { _; }
        else if (balanceOf(msg.sender) == 0) { _; }
        else { revert("You've already minted your allocation!"); }
    }

    // Confirm the msg.sender either owns the _tokenId NFT or previously burned it
    modifier tokenHolder(uint256 _tokenId) {
        if (ownerOf(_tokenId) == msg.sender || _burner[_tokenId] == msg.sender) { _; }
        else { revert("You do not own this token!"); }
    }

    modifier auctioneer() {
        require(msg.sender == _auctionWallet, "Only auction wallet can call this function!");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() ERC721("Ordinal Ducks", "OrdinalDucksNFT") payable { }

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
        isWhitelisted[1][_auctionWallet] = false;
        _auctionWallet = _address;
        isWhitelisted[1][_auctionWallet] = true;
    }

    // Consume whitelist allocation, removing msg.sender from whitelist
    function _consumeWL(address _address) internal {
        if (_address == _zodomoWallet || _address == _auctionWallet) { return; }
        for (uint i = 0; i < 5;) {
            if (isWhitelisted[i][_address]) {
                isWhitelisted[i][_address] = false;
                break;
            }
            unchecked { ++i; }
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

    // Change whitelist timestamp. Must be set 60 minutes into the future or further.
    function setWLTimestamp_(uint256 _timestamp) public onlyOwner {
        require(_timestamp >= (block.timestamp + 60 minutes), "Timestamp is too close!");
        wlTimestamp = _timestamp;
    }

    // Assign an address to a specific whitelist tier
    function whitelistAddress_(address _address, uint256 _tier) public onlyOwner {
        if (_tier == 0) {
            for (uint i = 1; i < 5;) {
                if (isWhitelisted[i][_address]) {
                    revert("A team wallet cannot have another whitelist!");
                }
            }
            isWhitelisted[_tier][_address] = !isWhitelisted[_tier][_address];
        }
        else if (_tier == 1) {
            for (uint i = 0; i < 5;) {
                if (isWhitelisted[i][_address]) {
                    revert("The auction wallet cannot have another whitelist!");
                }
            }
            _changeAuctionWallet(_address);
        }
        else if (_tier > 1 && _tier < 5) {
            require(!isWhitelisted[0][_address], "Team wallets cannot be added to general whitelist!");
            require(!isWhitelisted[1][_address], "Auction wallet cannot be added to general whitelist!");
            isWhitelisted[_tier][_address] = !isWhitelisted[_tier][_address];
        }
        else {
            revert("Invalid WL tier!");
        }
    }

    // Handle auction wallet batch mint
    function auctionBatchMint_() public mintable auctioneer {
        uint256 auctioneerBalance = balanceOf(_auctionWallet);
        for (uint256 i; i < 30 - auctioneerBalance;) {
            _safeMint(_auctionWallet, nftCount);
            ++nftCount;
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
    // Only one mint per address except for Zodomo
    function safeMint() public mintable mintLimit nonReentrant {
        _consumeWL(msg.sender);
        _safeMint(msg.sender, nftCount);
        ++nftCount;
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