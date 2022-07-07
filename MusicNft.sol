// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/** 
    Music NFT is an NFT smart contract that lets users 
    - Mints new music NFTs with price tag
    - Sell off the NFT to other users
    - Buy NFTs from other users
    - Rent out the NFT to other users for a specific duration
        - The amount paid for each rent is dependent on the duration
        - Renters pay 1/100 of the NFT price for each day in rent
        - Only one user can rent a music NFT at a time
        - When the rent is due, the NFT owner can "retrieve" the NFT from the user renting it
*/

contract MusicNFT is ERC721, Ownable, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private tokenId;

    mapping(uint256 => MusicToken) private musicTokens;
    // keeps track of tokens in market
    mapping(uint256 => bool) private ownedByContract;
    // keeps track of availability of tokens for rent
    mapping(uint256 => bool) public availableRent;

    event Mint(uint256 id, address user);
    event Buy(uint256 id, address indexed buyer);
    event Rent(uint256 id, address indexed to);
    event Retrieve(uint256 id, address indexed from);

    struct MusicToken {
        uint256 tokenId;
        address payable owner;
        uint256 price;
        address payable rentedTo;
        uint256 rentedAt;
        uint256 rentDuration;
        bool inMarket;
        bool sold;
    }

    constructor() ERC721("MusicNFT", "MST") {}

    // makes sure caller is the owner of NFT
    modifier isOwner(uint256 _tokenId) {
        require(
            ownerOf(_tokenId) == msg.sender ||
                musicTokens[_tokenId].owner == msg.sender,
            "only token owner can perform operation"
        );
        _;
    }
    // checks if NFT is able to be listed for rent or in the marketplace
    modifier canList(uint256 _tokenId) {
        require(
            !musicTokens[_tokenId].inMarket && musicTokens[_tokenId].sold,
            "Token is already in the market"
        );
        _;
    }

    // list token to market for sale
    function listToken(uint256 _tokenId)
        public
        isOwner(_tokenId)
        canList(_tokenId)
    {
        require(!availableRent[_tokenId], "Token is on rent");
        ownedByContract[_tokenId] = true;
        musicTokens[_tokenId].inMarket = true;
        musicTokens[_tokenId].sold = false;
        _transfer(msg.sender, address(this), _tokenId);
    }

    // list token to market for rent
    function listForRent(uint256 _tokenId)
        public
        isOwner(_tokenId)
        canList(_tokenId)
    {
        require(!availableRent[_tokenId], "Token is on rent");
        availableRent[_tokenId] = true;
    }

    // unlists token from market either from sale or rent
    function unList(uint256 _tokenId) public isOwner(_tokenId) {
        require(
            (availableRent[_tokenId] || musicTokens[_tokenId].inMarket) &&
                musicTokens[_tokenId].rentedTo == address(0),
            "Token isn't listed"
        );
        if (availableRent[_tokenId]) {
            availableRent[_tokenId] = false;
        } else {
            ownedByContract[_tokenId] = false;
            musicTokens[_tokenId].inMarket = false;
            musicTokens[_tokenId].sold = true;
            _transfer(address(this), msg.sender, _tokenId);
        }
    }

    // mint new token
    function mint(string calldata _tokenURI, uint256 _price) public {
        require(_price > 0, "Invalid token price");
        require(bytes(_tokenURI).length > 0, "Invalid URI");
        uint256 newId = tokenId.current();
        tokenId.increment();

        _safeMint(msg.sender, newId);
        _setTokenURI(newId, _tokenURI);

        // create music NFT
        musicTokens[newId] = MusicToken(
            newId,
            payable(msg.sender),
            _price,
            payable(address(0)),
            0,
            0,
            false,
            true // sold is initialised as true since token isn't listed on the market by default
        );

        emit Mint(newId, msg.sender);
    }

    // buy music token from market
    function buyNft(uint256 _tokenId) public payable {
        MusicToken storage token = musicTokens[_tokenId];
        require(token.inMarket && !token.sold, "token sold/not yet in market");
        require(
            token.rentedTo == address(0) && token.rentDuration == 0,
            "can't buy a token on rent"
        );
        require(token.owner != msg.sender, "Can't buy your own token");
        require(msg.value == token.price, "Send more funds!");
        address payable prevOwner = musicTokens[_tokenId].owner;
        uint256 value = token.price;

        // reset music nft properties
        token.owner = payable(msg.sender);
        token.rentedTo = payable(address(0));
        token.rentedAt = 0;
        token.rentDuration = 0;
        token.sold = true;
        token.inMarket = false;

        _transfer(address(this), msg.sender, _tokenId);
        ownedByContract[_tokenId] = false;
        (bool success, ) = prevOwner.call{value: value}("");
        require(success, "Payment failed");

        emit Buy(_tokenId, msg.sender);
    }

    function getRentPrice(uint256 _tokenId, uint256 _duration)
        public
        view
        returns (uint256)
    {
        return (musicTokens[_tokenId].price / 100) * (_duration / 1 days);
    }

    // rent token
    function rentNft(uint256 _tokenId, uint256 _duration)
        public
        payable
        canList(_tokenId)
    {
        uint256 rentCost = getRentPrice(_tokenId, _duration);
        require(availableRent[_tokenId], "Token is already on rent");
        require(_duration >= 1 days, "duration too low!");
        require(_duration <= 100 days, "duration too high");
        require(msg.value == rentCost, "Send more funds!");
        require(
            musicTokens[_tokenId].owner != msg.sender,
            "Can't rent your own token"
        );
        musicTokens[_tokenId].rentedTo = payable(msg.sender);
        musicTokens[_tokenId].rentDuration = _duration;
        musicTokens[_tokenId].rentedAt = uint256(block.timestamp);
        musicTokens[_tokenId].inMarket = false;
        availableRent[_tokenId] = false;
        // token is borrowed and temporarily transferred to renter
        _transfer(musicTokens[_tokenId].owner, msg.sender, _tokenId);
        _approve(address(this), _tokenId);
        (bool sent, ) = musicTokens[_tokenId].owner.call{value: rentCost}("");
        require(sent, "Payment for rent failed");
        emit Rent(_tokenId, msg.sender);
    }

    // claim token after rent expires
    function retrieveNft(uint256 _tokenId) public {
        MusicToken storage token = musicTokens[_tokenId];
        require(
            musicTokens[_tokenId].owner == msg.sender,
            "invalid owner query for token!"
        );
        require(
            !availableRent[_tokenId] &&
                !musicTokens[_tokenId].inMarket &&
                token.rentedTo != address(0),
            "Token isn't being rented"
        );
        require(
            block.timestamp > 1, // (token.rentedAt + token.rentDuration)
            "rent not yet expired"
        );
        address renter = token.rentedTo;
        // reset NFT properties
        token.rentedTo = payable(address(0));
        token.rentedAt = 0;
        token.rentDuration = 0;
        _transfer(renter, token.owner, _tokenId);
        emit Retrieve(_tokenId, msg.sender);
    }

    // get a single music token
    function getToken(uint256 _tokenId)
        public
        view
        returns (
            uint256 id,
            address owner,
            uint256 price,
            address rentedTo,
            uint256 rentedAt,
            uint256 rentDuration,
            bool inMarket,
            bool sold
        )
    {
        require(_exists(_tokenId), "Query for nonexistent token");
        id = _tokenId;
        owner = musicTokens[_tokenId].owner;
        price = musicTokens[_tokenId].price;
        rentedTo = musicTokens[_tokenId].rentedTo;
        rentedAt = musicTokens[_tokenId].rentedAt;
        rentDuration = musicTokens[_tokenId].rentDuration;
        inMarket = musicTokens[_tokenId].inMarket;
        sold = musicTokens[_tokenId].sold;
    }

    // get all music NFTs
    function getAllMusicNfts() public view returns (MusicToken[] memory) {
        uint256 inMarketCount;
        for (uint256 i = 0; i < tokenId.current(); i++) {
            if (musicTokens[i].inMarket) inMarketCount++;
        }

        uint256 counter;
        MusicToken[] memory _musicNfts = new MusicToken[](inMarketCount);
        for (uint256 i = 0; i < tokenId.current(); i++) {
            if (musicTokens[i].inMarket) {
                _musicNfts[counter] = musicTokens[i];
                counter++;
            }
        }
        return _musicNfts;
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 _tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(_tokenId);
    }

    // Changes is made to approve to prevent the renter from stealing the token
    function approve(address to, uint256 _tokenId) public override {
        require(
            msg.sender == musicTokens[_tokenId].owner ||
                ownedByContract[_tokenId],
            "Caller has to be owner of NFT"
        );
        super.approve(to, _tokenId);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     * Changes is made to approve to prevent the renter from stealing the token
     */
    function transferFrom(
        address from,
        address to,
        uint256 _tokenId
    ) public override {
        require(
            msg.sender == musicTokens[_tokenId].owner ||
                ownedByContract[_tokenId],
            "Caller has to be owner of NFT"
        );
        super.transferFrom(from, to, _tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     * Changes is made to approve to prevent the renter from stealing the token
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 _tokenId,
        bytes memory data
    ) public override {
        require(
            msg.sender == musicTokens[_tokenId].owner ||
                ownedByContract[_tokenId],
            "Caller has to be owner of NFT"
        );
        _safeTransfer(from, to, _tokenId, data);
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(_tokenId);
    }
}
