// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract Airdrop is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    /// @dev keccak256 EXTERNAL_ADMIN_ROLE hash
    bytes32 public constant EXTERNAL_ADMIN_ROLE = keccak256("EXTERNAL_ADMIN_ROLE");

    /// @dev airdrop infos
    struct AirDropInfo {
        uint256 endTimestamp;
        mapping(address => uint256) claimWhitelist;
        EnumerableSet.AddressSet _whitelistKeys;
    }

    /// @dev from address to airdrop info map
    mapping(address => AirDropInfo) private airDropInfos;

    /// @dev airdrop tokens
    EnumerableSet.AddressSet private airDropTokens;

    event Registered(address token_, address add_, uint256 amount_);
    event Claimed(address token_, address add_, uint256 amount_);
    event CleanCandidate(address token_, address add_, uint256 amount);
    event NewAirDrop(address token_, uint256 endTimestamp_);

    constructor(
        address[] memory airdropTokens_,
        uint256[] memory endTimestamps_
    ) public {
        require(
            airdropTokens_.length == endTimestamps_.length,
            "length dont match!!!"
        );
        require(airdropTokens_.length > 0, "length < 0!!!");

        for (uint256 i = 0; i < airdropTokens_.length; i++) {
            _setAirdropToken(airdropTokens_[i], endTimestamps_[i]);
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice only owner
     */
    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not owner!!!");
        _;
    }

    /**
     * @notice only owner or external admin
     */
    modifier onlyExternalAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
                hasRole(EXTERNAL_ADMIN_ROLE, msg.sender),
            "not external admin or owner!!!"
        );
        _;
    }

    /**
     * @notice token in airdrop tokens list
     */
    modifier tokenIn(address airDropToken_) {
        require(
            airDropTokens.contains(airDropToken_),
            "airDropToken_ not exit!!!"
        );
        _;
    }

    receive() external payable {}

    fallback() external payable {}

    /*
     * @dev Pull out all balance of token or BNB in this contract. When tokenAddress_ is 0x0, will transfer all BNB to the admin owner.
     */
    function pullFunds(address tokenAddress_) public onlyOwner {
        uint256 _bal;
        if (tokenAddress_ == address(0)) {
            _bal = address(this).balance;
            if (_bal > 0) {
                _msgSender().transfer(_bal);
            }
        } else {
            IERC20 token = IERC20(tokenAddress_);
            _bal = token.balanceOf(address(this));
            if (_bal > 0) {
                token.transfer(_msgSender(), _bal);
            }
        }
    }

    /**
     * @dev set Airdrop token address
     * @param airdropToken_ Airdrop token address
     * @param endTimestamp_ Airdrop end timestamp
     */
    function setAirdropToken(address airdropToken_, uint256 endTimestamp_)
        public
        onlyExternalAdmin
    {
        _setAirdropToken(airdropToken_, endTimestamp_);
    }

    function _setAirdropToken(address airdropToken_, uint256 endTimestamp_)
        internal
    {
        require(airdropToken_ != address(0), "airdrop token address zero!!!");
        airDropInfos[airdropToken_].endTimestamp = endTimestamp_;
        airDropTokens.add(airdropToken_);

        emit NewAirDrop(airdropToken_, endTimestamp_);
    }

    /**
     * @dev set whitelist, including candidates, values
     * @param airDropToken_ airdrop token
     * @param candidates_ somebody who can claim airdrop
     * @param values_ claim amount
     * @param singleValue_ claim amount
     */
    function setupWhitelist(
        address airDropToken_,
        address[] calldata candidates_,
        uint256[] calldata values_,
        uint256 singleValue_
    ) public onlyExternalAdmin tokenIn(airDropToken_) returns (bool) {
        require(candidates_.length > 0, "The length is 0");

        AirDropInfo storage info = airDropInfos[airDropToken_];

        if (values_.length == 0) {
            for (uint256 i = 0; i < candidates_.length; i++) {
                require(candidates_[i] != address(0), "address zero!!!");

                info.claimWhitelist[candidates_[i]] = singleValue_;
                info._whitelistKeys.add(candidates_[i]);

                emit Registered(airDropToken_, candidates_[i], singleValue_);
            }
        } else {
            require(
                candidates_.length == values_.length,
                "Value lengths do not match."
            );

            for (uint256 i = 0; i < candidates_.length; i++) {
                require(candidates_[i] != address(0), "address zero!!!");

                info.claimWhitelist[candidates_[i]] = values_[i];
                info._whitelistKeys.add(candidates_[i]);

                emit Registered(airDropToken_, candidates_[i], values_[i]);
            }
        }

        return true;
    }

    /**
     * @dev clean the whitelist of token
     */
    function cleanWhitelist(address airDropToken_)
        public
        onlyExternalAdmin
        tokenIn(airDropToken_)
        returns (bool)
    {
        AirDropInfo storage info = airDropInfos[airDropToken_];

        uint256 length = info._whitelistKeys.length();
        for (uint256 i = 0; i < length; i++) {
            // modify fix 0 position while iterating all keys
            address key = info._whitelistKeys.at(0);

            emit CleanCandidate(airDropToken_, key, info.claimWhitelist[key]);

            delete info.claimWhitelist[key];
            info._whitelistKeys.remove(key);
        }

        require(info._whitelistKeys.length() == 0);

        return true;
    }

    /**
     * @dev remove tokens from airdrop tokens
     */
    function removeAirDropToken(address airDropToken_)
        public
        onlyExternalAdmin
        tokenIn(airDropToken_)
        returns (bool)
    {
        delete airDropInfos[airDropToken_];
        return airDropTokens.remove(airDropToken_);
    }

    /**
     * @notice  airdrop tokens list
     */
    function getAirDropTokens() public view returns (address[] memory) {
        uint256 len = airDropTokens.length();
        address[] memory tokens = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            tokens[i] = airDropTokens.at(i);
        }
        return tokens;
    }

    /**
     * @notice get user claim airDropToken_ amount
     */
    function getClaimAmount(address airDropToken_, address user_)
        public
        view
        returns (uint256)
    {
        return airDropInfos[airDropToken_].claimWhitelist[user_];
    }

    function getEndTimestamp(address airDropToken_)
        public
        view
        returns (uint256)
    {
        return airDropInfos[airDropToken_].endTimestamp;
    }

    /**
     * @notice the remaining sum claimable amount
     */
    function sumClaimableAmount(address airDropToken_)
        public
        view
        returns (uint256 sum)
    {
        AirDropInfo storage info = airDropInfos[airDropToken_];

        uint256 length = info._whitelistKeys.length();
        for (uint256 i = 0; i < length; i++) {
            sum = sum.add(info.claimWhitelist[info._whitelistKeys.at(i)]);
        }
    }

    /**
     * @notice the remaining claimable address
     */
    function whitelistLength(address airDropToken_)
        public
        view
        returns (uint256)
    {
        return airDropInfos[airDropToken_]._whitelistKeys.length();
    }

    function _claim(address airDropToken_) internal {
        AirDropInfo storage info = airDropInfos[airDropToken_];

        if (block.timestamp >= info.endTimestamp) {
            return;
        }

        uint256 amount = info.claimWhitelist[msg.sender];
        if (amount > 0) {
            delete info.claimWhitelist[msg.sender];
            info._whitelistKeys.remove(msg.sender);

            emit Claimed(airDropToken_, msg.sender, amount);

            IERC20 token = IERC20(airDropToken_);
            require(token.transfer(msg.sender, amount), "Token transfer failed");
        }
    }

    /**
     * @dev claim airdrop
     */
    function claim() public returns (bool) {
        for (uint256 i = 0; i < airDropTokens.length(); i++) {
            _claim(airDropTokens.at(i));
        }
        return true;
    }
}
