// SPDX-License-Identifier: MIT 

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/** 
    Music NFT is an NFT smart contract that let's users 
    - Mints new music NFTs with price tag
    - Sell off the NFT to other users
    - Buy NFTs from other users
    - Rent out the NFT to other users for a specific duration
        - The amount paid for each rent is dependent on the duration
        - Renters pay 1/100 of the NFT price for each day in rent
        - Only one user can rent a music NFT per time
        - When the rent is due, the NFT owner can "retrieve" the NFT from the user renting it
*/

contract MusicNFT is Ownable, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private tokenId;

    mapping(uint256 => MusicToken) private musicTokens;

    event Mint(uint256 id);
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

    // list token to market
    function listToken(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "only token owner can perform operation");
        _transfer(msg.sender, address(this), _tokenId);
        musicTokens[_tokenId].inMarket = true;
        musicTokens[_tokenId].sold = false;
    }

    // mint new token
    function mint(string calldata _tokenURI, uint256 _price) public {
        require(_price > 0, "Invalid token price");
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
            false
        );  

        emit Mint(newId);      
    }

    // buy music token from market
    function buyNft(uint256 _tokenId) public payable {
        MusicToken storage token = musicTokens[_tokenId];
        require(msg.value >= token.price, "Send more funds!");   
        require(token.inMarket, "token sold/not yet in market");
        require(token.rentedTo == address(0), "can't buy token in rent");
        require(!token.sold, "token not in market");

        address prevOwner = musicTokens[_tokenId].owner;
        uint256 value = token.price;        

        // reset music nft properties
        token.owner = payable(msg.sender);
        token.rentedTo = payable(address(0));
        token.rentedAt = 0;
        token.rentDuration = 0;
        token.sold = true; 
        token.inMarket = false;

        _transfer(address(this), msg.sender, _tokenId);
        payable(prevOwner).transfer(value);

        emit Buy(_tokenId, msg.sender);
    }

    // rent token
    function rentNft(uint256 _tokenId, uint256 _duration) public payable {
        uint256 rentCost = (musicTokens[_tokenId].price / 100) * (_duration / 1 days);
        require(_duration >= 1 days, "duration too low!");
        require(_duration <= 100 days, "duration too high");
        require(msg.value >= rentCost, "Send more funds!");
        require(musicTokens[_tokenId].inMarket, "token sold/not yet in market");
        require(!musicTokens[_tokenId].sold, "token already sold");

        musicTokens[_tokenId].rentedTo = payable(msg.sender); 
        musicTokens[_tokenId].rentDuration = _duration;  
        musicTokens[_tokenId].rentedAt = uint256(block.timestamp);
        musicTokens[_tokenId].inMarket = false;

        payable(musicTokens[_tokenId].owner).transfer(rentCost);  

        emit Rent(_tokenId, msg.sender); 
    }

    // claim token after rent expires
    function retrieveNft(uint256 _tokenId) public {
        MusicToken storage token = musicTokens[_tokenId];
        require(musicTokens[_tokenId].owner == msg.sender, "invalid owner query for token!");
        require(token.rentedTo != address(0), "token not on rent");
        require(block.timestamp >= (token.rentedAt + token.rentDuration), "rent not yet expired");

        // reset NFT properties
        token.rentedTo = payable(address(0));
        token.rentedAt = 0;
        token.rentDuration = 0;

        emit Retrieve(_tokenId, msg.sender);
    }

    // get a single music token
    function getToken(uint256 _tokenId) public view returns (
        uint256 id,
        address owner,
        uint256 price,
        address rentedTo,
        uint256 rentedAt,
        uint256 rentDuration,
        bool inMarket,
        bool sold
    ) {
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
}
