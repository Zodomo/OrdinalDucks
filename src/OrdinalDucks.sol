// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";

/// @title An ERC721 contract that mints placeholder NFTs that a recipient can burn alongside providing a Bitcoin address for the team to manually send their ordinal to.
/// @author Zodomo
/// @notice This contract is designed with the idea in mind that the team would be manually managing sending ordinals to their recipients as to avoid using complicated technologies like the Emblem Vaults.
contract OrdinalDucks is ERC721, Ownable, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                EVENTS & ERRORS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    event Whitelist(address indexed _address, uint256 indexed _tier, bool indexed _bool);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                STORAGE
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    uint256 public immutable maxSupply;
    uint256 public constant maxPerMint = 1;
    uint256 public wlTimestamp;
    uint256 public price;
    mapping(uint256 => mapping(address => bool)) public whitelist;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isPriceExempt;
    bool public mintCompleted;
    string public baseURI;
    
    uint256 private _nftCount = 0;
    bool private _auctionMinted;
    bool private _devMinted;
    mapping(uint256 => string) private _burnAddress;
    mapping(uint256 => address) private _burner;
    address private _auctionWallet;
    address private _devWallet;
    bytes1[4] private taprootPrefix = [bytes1('b'),bytes1('c'),bytes1('1'),bytes1('p')];

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Confirm the msg.sender has mint privileges
    modifier mintable() {
        require(_nftCount < maxSupply, "NFT supply cap reached!");
        if (whitelist[0][msg.sender]) { _; } // Auction WL mints
        else if (whitelist[1][msg.sender]) { _; } // One / OG WL mint
        else if (whitelist[2][msg.sender]) { _; } // Dev / Top D's 2 WL mints
        else if (whitelist[3][msg.sender] && block.timestamp >= wlTimestamp) { _; } // Waddler WL
        else if (block.timestamp >= (wlTimestamp + 30 minutes)) { _; } // Decoy / General Mint
        else { revert("Mint conditions are not met!"); }
    }

    // Impose mint limit based on WL tier
    modifier mintLimit() {
        if (whitelist[0][msg.sender] && balanceOf(msg.sender) < 30) { _; } // Auction wallet
        else if (whitelist[2][msg.sender] && balanceOf(msg.sender) < 2) { _; } // Dev + Top D's
        else if ((whitelist[1][msg.sender] || whitelist[3][msg.sender]) && balanceOf(msg.sender) < 1) { _; } // One WL / Waddlers
        else if (block.timestamp >= (wlTimestamp + 30 minutes) && balanceOf(msg.sender) < 1) { _; } // Everyone else after whitelist
        else { revert("Mint limitation hit!"); }
    }

    // Require mint is complete
    modifier mintComplete() {
        require(mintCompleted, "Mint cap not reached!");
        _;
    }

    // Confirm the msg.sender either owns the _tokenId NFT or previously burned it
    modifier tokenHolder(uint256 _tokenId) {
        if (_ownerOf(_tokenId) == msg.sender || _burner[_tokenId] == msg.sender) { _; }
        else { revert("You do not own this token!"); }
    }

    // Confirm the msg.sender is the auction wallet
    modifier auctioneer() {
        require(msg.sender == _auctionWallet, "Only auction wallet can call this function!");
        require(_devMinted, "Dev hasn't minted yet!");
        _;
    }

    // Confirm whitelist is not yet active
    modifier wlOff() {
        require(block.timestamp < wlTimestamp, "Whitelist is already active!");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        address _auction,
        address _dev,
        string memory _uri,
        uint256 _timestamp,
        uint256 _price
    ) ERC721("Ordinal Ducks", "ORDINALDUCKS") payable {
        maxSupply = 150;
        whitelist[0][_auction] = true;
        whitelist[2][_dev] = true;
        _auctionWallet = _auction;
        _devWallet = _dev;
        isPriceExempt[_auction] = true;
        isPriceExempt[_dev] = true;
        baseURI = _uri;
        wlTimestamp = _timestamp;
        price = _price;
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
    function totalSupply() public view returns (uint256) {
        uint256 supply = _nftCount;
        if (_auctionMinted) { supply += 29; }
        if (_devMinted) { supply += 1; }
        return supply;
    }

    // Return mint price for buildship interface
    function getPrice() public view returns (uint) {
        return price;
    }

    // Return wallet mint cap for buildship interface
    function viewMintCap() public view returns (uint) {
        if (msg.sender == _auctionWallet) { return 30; }
        else if (msg.sender == _devWallet) { return 2; }
        else if (whitelist[2][msg.sender]) { return 2; }
        else { return 1; }
    }

    // Check if whitelisted
    function checkWhitelist(uint256 _tier, address _address) public view returns (bool) {
        return whitelist[_tier][_address];
    }

    // Retrieve burner's Bitcoin address to receive their respective inscription
    function getBurnAddress(uint256 _tokenId) public view returns (string memory) {
        return _burnAddress[_tokenId];
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
        uint256 bal = 121 + balanceOf(msg.sender);
        for (uint256 i = bal; i <= 150; i++) {
            if (_ownerOf(i) == _devWallet) { continue; }
            _safeMint(_auctionWallet, i);
        }
        _auctionMinted = true;
    }

    // Randomize token ID, attempt 10 runs before locating available ID
    function _randomId() internal view returns (uint256) {
        for (uint256 i; i < 10;) {
            uint256 index = uint256(keccak256(abi.encodePacked(
                block.timestamp, blockhash(block.number - 1), block.difficulty, msg.sender, i))) % (121);
            if (_ownerOf(index) == address(0) && index > 0 && index <= 120) {
                return index;
            }
            unchecked { ++i; }
        }
        for (uint256 i = 1; i <= 120;) {
            if (_ownerOf(i) == address(0)) {
                return i;
            }
            unchecked { ++i; }
        }
        return 0;
    }

    // Process mint logic/distribution for different whitelist tiers
    function _mintRouter() internal returns (uint256) {
        // If auction wallet is msg.sender, process auction mint logic
        if (whitelist[0][msg.sender]) {
            _auctionBatchMint();
            if (totalSupply() == 150) { mintCompleted = true; }
            return 0;
        }
        // Allocate one randomized grailed mint to dev
        else if (msg.sender == _devWallet && balanceOf(_devWallet) < 1) {
            uint256 tokenId = 121 + (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % 30);
            _safeMint(_devWallet, tokenId);
            _devMinted = true;
            return tokenId;
        }
        // Process mints for everyone else
        // Restrictions are pre-imposed before the mint routing logic
        else {
            uint256 tokenId = _randomId();
            _safeMint(msg.sender, tokenId);
            ++_nftCount;
            if (totalSupply() == 150) { mintCompleted = true; }
            return tokenId;
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

    // Change whitelist timestamp, locks after whitelist is active
    function setWLTimestamp_(uint256 _timestamp) public wlOff onlyOwner {
        require(_timestamp > block.timestamp, "Timestamp not in future!");
        wlTimestamp = _timestamp;
    }

    // Assign an address to a specific whitelist tier
    // Calling on an address a second time will remove whitelist
    function whitelistAddress_(address _address, uint256 _tier) public wlOff onlyOwner {
        // Deny changes to _devWallet
        require(_address != _devWallet, "Cannot change dev wallet WL status!");
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

    // whitelistAddress_ batch version
    function whitelistAddressBatch_(address[] memory _addresses, uint256[] memory _tier) public wlOff onlyOwner {
        require(_addresses.length == _tier.length, "Argument arrays are not of equal length!");
        for (uint256 i; i < _addresses.length;) {
            whitelistAddress_(_addresses[i], _tier[i]);
            unchecked { ++i; }
        }
    }

    // Change the mint price, locks after whitelist is active
    function changePrice_(uint256 _price) public wlOff onlyOwner {
        price = _price;
    }

    // Toggle price exemption for specified address
    function togglePriceExempt_(address _address) public wlOff onlyOwner {
        isPriceExempt[_address] = !isPriceExempt[_address];
    }

    // togglePriceExempt_() batch version
    function togglePriceExemptBatch_(address[] memory _addresses) public wlOff onlyOwner {
        for (uint256 i; i < _addresses.length;) {
            togglePriceExempt_(_addresses[i]);
            unchecked { ++i; }
        }
    }

    // Withdraw function
    function withdraw_() public onlyOwner {
        address payable payee = payable(_auctionWallet);
        (bool success,) = payee.call{ value: address(this).balance }("");
        require(success, "Withdraw failed!");
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    // Mint NFT token
    // The _nTokens parameter is deliberately unused but is included to satisfy Buildship button requirements
    function mint(uint256 _nTokens) public mintable mintLimit nonReentrant payable returns (uint256) {
        if (!isPriceExempt[msg.sender]) {
            require(msg.value >= price, "Payment not sufficient!");
        }
        return _mintRouter();
    }

    // Burn _tokenId NFT in exchange for Bitcoin address
    function burn(uint256 _tokenId, string memory _btcAddress) public tokenHolder(_tokenId) {
        checkTaprootAddress(_btcAddress);
        if (_ownerOf(_tokenId) == msg.sender) {
            _burner[_tokenId] = msg.sender;
            _burnAddress[_tokenId] = _btcAddress;
            _burn(_tokenId);
        }
        else {
            _burnAddress[_tokenId] = _btcAddress;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////
                MISCELLANEOUS FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////////////////////////*/

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(_baseURI(), "contract.json"));
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_tokenId > 0 && _tokenId <= maxSupply, "Token ID is out of range!");
        return super.tokenURI(_tokenId);
    }

    receive() external payable {}
    fallback() external payable {}
}