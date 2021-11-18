
contract NFTART is ERC721Enumerable, Ownable, ERC721Burnable, ERC721Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdTracker;

    uint256 public  MAX_ELEMENTS = 100;
    uint256 public  PRICE = 25000000000000000;
    uint256 public  MAX_BY_MINT = 100;
    address public Team =  address(0); // TODO set an address for ownership
    struct TokenInfos {
        uint256 id;
        string uri;
    }
    mapping(uint256=>TokenInfos) public tokenidInfos;
    
    mapping(string => bool) public isMinted;

    address public creatorAddress;

    string public baseTokenURI;
    

    event CreateNFT(uint256 indexed id);
/*    constructor(string memory _title, string[] memory _hashes) ReentrancyGuard()
*/

    constructor(string memory _title, string[] memory _hashes) payable ERC721(_title,_title){
        creatorAddress = msg.sender;
        setBaseURI('https://ipfs.io/ipfs/');
        mint(msg.sender, _hashes);
        transferOwnership(Team);
    }
    
    modifier saleIsOpen {
        require(_totalSupply() <= MAX_ELEMENTS, "Sale end");
        if (_msgSender() != owner()) {
            require(!paused(), "Pausable: paused");
        }
        _;
    }

    function _totalSupply() internal view returns (uint) {
        return _tokenIdTracker.current();
    }

    function totalMint() public view returns (uint256) {
        return _totalSupply();
    }

    function mint(address _to, string[]memory _listHashes) public nonReentrant payable {
        uint256 value = msg.value;
        (bool success,) = payable(Team).call{value: value}(new bytes(0));
        if(!success)revert("mint: transfer error");
        uint256 total = _totalSupply();
        uint256 _count = _listHashes.length;
        require(total + _count <= MAX_ELEMENTS, "Max limit of NFTs reached!");
        require(_count>0, "Please, call at least for one element");
        require(total <= MAX_ELEMENTS, "All NFT's have been minted, sale ended");
        require(_count <= MAX_BY_MINT, "Your trying to mint too many NFTs! Please select a smaller amount");
        require(msg.value >= price(_count), "Value below price of NFT");


        for(uint256 i = 0; i<_count;i++){
            require(!isMinted[_listHashes[i]], "nft is not unique"); 
            string memory url = string(abi.encodePacked(baseTokenURI, _listHashes[i]));
            uint256 id = _totalSupply();
            TokenInfos memory infos = TokenInfos(id, url);
            tokenidInfos[id] = infos;
            _mintAnElement(_to);
            isMinted[_listHashes[i]] = true;
            
        }
    }

    function _mintAnElement(address _to) private {
        uint id = _totalSupply();
        _tokenIdTracker.increment();
        _safeMint(_to, id);
        emit CreateNFT(id);
    }

    function price(uint256 _count) public view  returns (uint256) {
        return PRICE.mul(_count);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function walletOfOwner(address _owner) external view returns (TokenInfos[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        
        TokenInfos[] memory tokensId = new TokenInfos[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 id = tokenOfOwnerByIndex(_owner, i);
            tokensId[i] = tokenidInfos[id] ;
        }

        return tokensId;
    }

    function pause(bool val) public onlyOwner {
        if (val == true) {
            _pause();
            return;
        }
        _unpause();
    }

    function withdrawAll() external onlyOwner nonReentrant{
        uint256 balance = address(this).balance;
        require(balance > 0, "balance is 0.");
        (bool success,) = payable(msg.sender).call{value: balance}(new bytes(0));
        if(!success)revert("withdrawAll: transfer error");
    }

    function withdraw(uint256 _amount) external onlyOwner nonReentrant{
        uint256 balance = address(this).balance;
        require(balance > 0, "balance is 0.");
        require(balance > _amount, "balance must be superior to amount");
        (bool success,) = payable(msg.sender).call{value: _amount}(new bytes(0));
        if(!success)revert("withdraw: transfer error");
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
   

    function tokenURI(uint256 _id) public override view returns(string memory){
        return tokenidInfos[_id].uri;
    }
    
    function setTeamAddress(address Team) external onlyOwner{
        Team = Team;
    }
    
    function setMaxElements(uint256 _MAX_ELEMENTS)external onlyOwner{
        MAX_ELEMENTS = _MAX_ELEMENTS;
    }
    
     function setPrice(uint256 _PRICE)external onlyOwner{
        PRICE = _PRICE;
    }
    
    function setMaxByMint(uint256 _MAX_BY_MINT)external onlyOwner{
        MAX_BY_MINT = _MAX_BY_MINT;
    }
   
    function sendEth() public payable nonReentrant{}
}
