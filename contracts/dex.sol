pragma solidity ^0.8.10;

pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Dex{
    
    struct Token{
        bytes32 ticker;
        address tokenAddress;
    }


    enum Side{
        BUY,
        SELL
    }

    struct Order{
        uint id;
        address trader;
        Side side;
        bytes32 ticker;
        uint amount;
        uint price;
        uint filled;
        uint date;
    }

    //For trade IDs
    uint public nextTradeID;

    //Address of Admin
    address public admin;
    
    //List of tokens that can be traded
    bytes32[] public tokenList;
    
    //Mapping tokens by ticker
    mapping(bytes32 => Token) public tokens;

    //Mapping balances of a trader for particular token
    mapping(address => mapping(bytes32 => uint256)) public traderBalances;
    
    //Orders mapped by token and Side(BUY = 0, SELL = 1)
    mapping(bytes32 => mapping(uint => Order[])) public orderBook;

    //Ticker for DAI
    bytes32 constant DAI = bytes32("DAI");

    //For Order ID
    uint public nextOrderID;

    constructor() public {
        //Deployer is the admin
        admin = msg.sender;
    }

    //Only admin can add a new token that can be traded on DEX
    //If tokens already exist, the function reverts
    function addToken(
        bytes32 ticker, 
        address tokenAddress) 
        external 
        onlyAdmin 
        tokenAlreadyExist(ticker){

        tokens[ticker] = Token(ticker, tokenAddress);
        tokenList.push(ticker);
    }

    //A user can deposit a token into the DEX iff token exists
    function deposit(
        uint amount, 
        bytes32 ticker) 
        external 
        tokenExist(ticker){
        
        _deposit(amount, ticker);
    }

    function _deposit(
        uint amount, 
        bytes32 ticker) 
        private{
            IERC20(tokens[ticker].tokenAddress)
                .transferFrom(msg.sender, address(this), amount);
            traderBalances[msg.sender][ticker] += amount;
        }

    //A user can withdraw balances from the contract 
    //We will check if token exist or not using modifier tokenExist(ticker)
    //We will check if trader has enough balance to withdraw
    function withdraw(
        uint amount, 
        bytes32 ticker) 
        external 
        tokenExist(ticker){

        require(
            traderBalances[msg.sender][ticker] >= amount, 
            "Balance insufficient"
            );
        _withdraw(amount, ticker);
        }

     function _withdraw(
        uint amount, 
        bytes32 ticker) 
        private
        {
        //We will keep a check on reentrancy by deducting amount from balances before we transfer tokens
        traderBalances[msg.sender][ticker] -= amount;
        bool sent = IERC20(tokens[ticker].tokenAddress).transfer(msg.sender, amount);
        require(sent, "Transaction failed");
    }


    //Checking if token is tradable on the DEX
    modifier tokenExist(bytes32 ticker){
        require(
            tokens[ticker].tokenAddress != address(0),
            "This token doesn't exist"
            );
        _;
    }

    //creating limit orders and checking if token exist
    //Also checking if token is DAI as DAI is not tradable
    
    function createLimitOrder(
        bytes32 ticker, 
        uint price, 
        uint amount, 
        Side side) 
        external 
        tokenExist(ticker)
        tokenNotDAI(ticker){
                  
            //If Sell order => Must have enough tokens to sell
            if(side == Side.SELL){
                require(
                    traderBalances[msg.sender][ticker] >= amount, 
                    "Insufficient token balance"
                    );
            }

            //If buy order => Must have enough balance of DAI to buy
            else{
                require(
                    traderBalances[msg.sender][DAI] >= amount*price, 
                    "DAI balance insufficient"
                    );
            }

            _createLimitOrder(ticker,price,amount,side);
        }

    function _createLimitOrder(
        bytes32 ticker, 
        uint price, 
        uint amount, 
        Side side) 
        private 
        {
        //Finding the orders of the token on required side 
        Order[] storage orders = orderBook[ticker][uint(side)];

        //Pushing the order into the orderBook array
        orders.push(Order(
            nextOrderID, 
            msg.sender, 
            side, 
            ticker, 
            amount, 
            price, 
            0, 
            block.timestamp
            ));
        //Checking so that there is no overflow problem
        uint i = (orders.length > 0)? orders.length - 1 : 0;
        
        //Rearranging orders in the order array
        while(i>0){
            //If side is buy and last buy order price is less than the 2nd last order, do Nothing
            if(side == Side.BUY && orders[i].price <= orders[i-1].price){
                break;
            }
            //If side is sell and last sell order price is higher than the 2nd last order, do Nothing
            if(side == Side.SELL && orders[i].price >= orders[i-1].price){
                break;
            }
            //If side is buy, then tokens should be arranged in highest price first mode
            //If side is sell, then tokens must be arranged in lowest price first mode
            //Arrange till one of the above conditions is met
            Order memory order = orders[i];
            orders[i] = orders[i-1];
            orders[i-1] = order;
            i--;
        }
    //Incrementing order ID
    nextOrderID++;
    }


    //Creating market orders and checking if token exist 
    //Also checking if token is DAI as DAI cannot be traded
    function createMarketOrder(
        bytes32 ticker, 
        uint amount, 
        Side side) 
        external 
        tokenExist(ticker) 
        tokenNotDAI(ticker){
        
        //If Sell order => Must have enough tokens to sell
        if(side == Side.SELL){
            require(
                traderBalances[msg.sender][ticker] >= amount, 
                "Insufficient token balance"
                );
        }
        _createMarketOrder(ticker, amount, side);
    }

    function _createMarketOrder(
        bytes32 ticker, 
        uint amount, 
        Side side) 
        private
        {
        //If buy order => We need to match it to sell orders
        //If sell order => We need to match it to buy orders
        Order[] storage orders = orderBook[ticker][uint(side == Side.BUY
                                                    ? Side.SELL
                                                    :Side.BUY
                                                    )];
        uint i;
        //Amount of token order remaining to be matched
        uint remaining = amount;

        //Matching orders if remaining order is not zero
        while(i<orders.length && remaining>0){
            //Available is the amount of tokens in the order left to be filled
            uint available = orders[i].amount- orders[i].filled;
            //Matched is the amount of tokens in the order that has been filled
            //If remaining is more than available, we will match what is available and go to next order
            //If available is more than remaining, then match remaining
            uint matched = (remaining>available)
                                ? available
                                : remaining;
            //Now remaining is low as we matched some order
            remaining -= matched;
            //Incrementing the filled field of order thar was used to match with market order
            orders[i].filled += matched;
            //Emitting trade
            emit NewTrade(
                nextTradeID, 
                orders[i].id, 
                ticker, 
                orders[i].trader, 
                msg.sender, matched, 
                orders[i].price, 
                block.timestamp
                );

            //Updating trader balances
            if(side == Side.SELL){
                //If side was sell => 
                //  then msg sender sold tokens and got DAI
                //  and the order[i] trader bought tokens and paid DAI
                traderBalances[msg.sender][ticker] -= matched;
                traderBalances[msg.sender][DAI] += matched*orders[i].price;
                traderBalances[orders[i].trader][ticker] += matched;
                traderBalances[orders[i].trader][DAI] -= matched*orders[i].price;
            }
            if(side == Side.BUY){
                //If side was buy => Check if msg sender has enough DAI
                require(
                    traderBalances[msg.sender][DAI] >= matched*orders[i].price, 
                    "DAI balance insufficient"
                    );
                //For buy => msg sender paid DAI and received tokens
                traderBalances[msg.sender][ticker] += matched;
                traderBalances[msg.sender][DAI] -= matched*orders[i].price;
                //Order[i] trader sold tokens and received DAI
                traderBalances[orders[i].trader][ticker] -= matched;
                traderBalances[orders[i].trader][DAI] += matched*orders[i].price;
            }
            //Incrementing Trade ID and i
            nextTradeID++;
            i++;
        }

        i=0;
        //Removing completely filled orders
        while(i<orders.length && orders[i].filled == orders[i].amount){
            for(uint j = i; j< orders.length-1; j++){
                orders[j] = orders[j+1];
            }
            orders.pop();
            i++;
        }
    }

    //View function to get order list for particular token and side
    function getOrders(
        bytes32 ticker, 
        Side side) 
        external 
        view 
        returns(Order[] memory) {

        return orderBook[ticker][uint(side)];
    }

    //View function for getting tokenlist
    function getTokens() external view returns(Token[] memory){
        //Copying tokenlist into a new array _tokens
        Token[] memory _tokens = new Token[](tokenList.length);
        for(uint i = 0; i< tokenList.length; i++){
            _tokens[i] = Token(tokens[tokenList[i]].ticker, tokens[tokenList[i]].tokenAddress);
        }
        return _tokens;
    }

    function changeAdmin(address newAdmin) external onlyAdmin{
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin, block.timestamp);
    }


/* <------------------Modifiers-------------------> */

    //Only admin can pass this gate
    modifier onlyAdmin(){
        require(
            msg.sender == admin, 
            "only admin allowed"
            );
        _;
    }

    //Checking if token is tradable on the dex
    modifier tokenAlreadyExist(bytes32 ticker){
        for(uint i=0; i<tokenList.length;i++)
        {
            if(ticker == tokenList[i]){
                revert("Token already exists");
            }
        }
        _;
    }

    //If token is DAI, we cannot trade it on DEX
    modifier tokenNotDAI(bytes32 ticker){
        require(ticker != DAI, "DAI not tradable");
        _;
    }

    /*<----------------Events----------------------> */
    event NewTrade(
        uint tradeID,
        uint orderID,
        bytes32 indexed ticker,
        address indexed trader1,
        address indexed trader2,
        uint amount,
        uint price,
        uint date
        );

    event AdminChanged(
        address oldAdmin,
        address newAdmin,
        uint date
    );
}