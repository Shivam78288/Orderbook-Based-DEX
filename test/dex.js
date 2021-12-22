const {expectRevert} = require("@openzeppelin/test-helpers");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");

const Dai = artifacts.require('dai.sol');
const Bat = artifacts.require('bat.sol');
const Rep = artifacts.require('rep.sol');
const Zrx = artifacts.require('zrx.sol');
const Dex = artifacts.require('dex.sol');

contract ('Dex', (accounts) =>{
    let dex, dai, bat, rep, zrx;
    const SIDE = {
        BUY:0,
        SELL:1
    }
    const [trader1, trader2] = [accounts[1], accounts[2]];
    const [DAI,BAT, REP, ZRX] = ['DAI', 'BAT', 'REP', 'ZRX'].map(ticker => web3.utils.fromAscii(ticker));
    
    beforeEach(async() => {
        [dai, bat, rep, zrx] = await Promise.all([Dai.new(),Bat.new(),Rep.new(),Zrx.new()]);
    
        dex = await Dex.new();
        await Promise.all([
            dex.addToken(DAI, dai.address),
            dex.addToken(BAT, bat.address),
            dex.addToken(REP, rep.address),
            dex.addToken(ZRX, zrx.address)
        ]);

        const amount = web3.utils.toWei('1000');
        const seedTokenBalance = async(token, trader) =>{
            await token.faucet(trader, amount);
            await token.approve(dex.address, amount, {from: trader});
        }

        await Promise.all([dai, bat, rep, zrx].map(token => seedTokenBalance(token,trader1)));
        await Promise.all([dai, bat, rep, zrx].map(token => seedTokenBalance(token,trader2)));

    });

    it('Do not add token if asked by non admin', async() => {
        await expectRevert(
            dex.addToken(DAI, dai.address, {from: trader1}), 
            "only admin allowed"
        );
    });

    it('Do not add token if it already exist', async() =>{
        await expectRevert(
            dex.addToken(DAI, dai.address), 
            "Token already exists"
        );
        
    });

    it('Deposit amount of tokens if token exists', async() => {
        const amount = web3.utils.toWei('100');
        await dex.deposit(amount, DAI, {from: trader1});
        const balance = await dex.traderBalances(trader1, DAI);
        assert(balance.toString() === amount);
    });

    it('Should not deposit if token does not exist', async() =>{
        await expectRevert(
            dex.deposit(web3.utils.toWei('100'), web3.utils.fromAscii('TOKEN'), {from: trader1}),
            "This token doesn't exist"
        );
    });

    it('should withdraw if token exist and traderBalance > amount',async() => {
        const amount = web3.utils.toWei('100');
        await dex.deposit(amount, DAI, {from: trader1});
        //Now trader1 has 100 DAI in the dex balance
        await dex.withdraw(amount, DAI, {from: trader1});
        //After withdrawal, trader1 balance of DAI must be 0 in dex balance
        const balanceDEX = await dex.traderBalances(trader1, DAI);
        const balanceDAI = await dai.balanceOf(trader1);
        assert(balanceDEX.toString() === '0');
        //Initial balance of DAI for trader1 was 1000
        assert(balanceDAI.toString() === web3.utils.toWei('1000'));
    });

    it('Should not withdraw if token does not exist', async() => {
        await expectRevert(
            dex.withdraw(web3.utils.toWei('100'), web3.utils.fromAscii('Token'), {from: trader1}),
            "This token doesn't exist"
        );
    });
    
    it('Should not withdraw if traderBalance < amount', async() => {
        const amount = web3.utils.toWei('100');
        await dex.deposit(amount, DAI, {from: trader1});
        await expectRevert(
            dex.withdraw(web3.utils.toWei('1000'), DAI, {from: trader1}),
            "Balance insufficient"
        );
    });

    it('Create limit order if tokenExists, tokenNotDai and person has enough balance', async() => {
        await dex.deposit(web3.utils.toWei('100'), DAI, {from: trader1});
        const amount = web3.utils.toWei('10');
        const price = 10;
        await dex.createLimitOrder(REP, price, amount, SIDE.BUY, {from: trader1});
        let buyOrders = await dex.getOrders(REP, SIDE.BUY);
        let sellOrders = await dex.getOrders(REP, SIDE.SELL);
        assert(buyOrders.length === 1);
        assert(buyOrders[0].trader === trader1);
        assert(buyOrders[0].ticker === web3.utils.padRight(REP, 64));
        assert(buyOrders[0].price === '10');
        assert(buyOrders[0].amount === web3.utils.toWei('10'));
        assert(sellOrders.length === 0);

        //Lets check if another trader makes an order, then it is added to order book
        await dex.deposit(web3.utils.toWei('200'), DAI, {from: trader2});
        let amountAfter = web3.utils.toWei('11');
        let priceAfter = 11;
        //Since its price is greater than prev order, it must be stored before the first order in array
        await dex.createLimitOrder(REP, priceAfter, amountAfter, SIDE.BUY, {from: trader2});
        buyOrders = await dex.getOrders(REP, SIDE.BUY);
        sellOrders = await dex.getOrders(REP, SIDE.SELL);
        assert(buyOrders.length === 2);
        assert(buyOrders[0].trader === trader2);
        assert(buyOrders[1].trader === trader1);
        assert(sellOrders.length === 0);

        //Lets check if trader2 makes another order, then it is added to order book
        await dex.createLimitOrder(REP, 9, web3.utils.toWei('5'), SIDE.BUY, {from: trader2});
        buyOrders = await dex.getOrders(REP, SIDE.BUY);
        sellOrders = await dex.getOrders(REP, SIDE.SELL);
        assert(buyOrders.length === 3);
        assert(buyOrders[0].trader === trader2);
        assert(buyOrders[1].trader === trader1);
        assert(buyOrders[2].trader === trader2);
        assert(sellOrders.length === 0);

    });

    it('Do not create limit order if token does not exist', async() =>{
        await dex.deposit(web3.utils.toWei('100'), DAI, {from: trader1});
        await expectRevert(
            dex.createLimitOrder(web3.utils.fromAscii('Token'), 10, web3.utils.toWei('10'), SIDE.BUY, {from: trader1}),
            "This token doesn't exist"
        );
    });


    it('Do not create limit order if token traded is DAI', async() =>{
        await dex.deposit(web3.utils.toWei('100'), DAI, {from: trader1});
        await expectRevert(
            dex.createLimitOrder(DAI, 10, web3.utils.toWei('10'), SIDE.BUY, {from: trader1}),
            "DAI not tradable"
        );
    });

    it('Do not create limit buy order if DAI not enough', async() =>{
        await dex.deposit(web3.utils.toWei('10'), DAI, {from: trader1});
        await expectRevert(
            dex.createLimitOrder(REP, 10, web3.utils.toWei('10'), SIDE.BUY, {from: trader1}),
            "DAI balance insufficient"
        );
    });

    it('Do not create limit sell order if token balance not enough', async() =>{
        await dex.deposit(web3.utils.toWei('10'), REP, {from: trader1});
        await expectRevert(
            dex.createLimitOrder(REP, 10, web3.utils.toWei('100'), SIDE.SELL, {from: trader1}),
            "Insufficient token balance"
        );
    });

    it('Create market order if everything is correct', async() => {
        await dex.deposit(web3.utils.toWei('200'), DAI, {from:trader1});
        let amount = web3.utils.toWei('10');
        let price = 10;
        await dex.createLimitOrder(REP, price, amount, SIDE.BUY, {from: trader1});
        await dex.deposit(web3.utils.toWei('100'), REP, {from: trader2});
        await dex.createMarketOrder(REP, web3.utils.toWei('5'), SIDE.SELL, {from: trader2});
        let balances = await Promise.all([
            dex.traderBalances(trader1, DAI),
            dex.traderBalances(trader1, REP),
            dex.traderBalances(trader2, DAI),
            dex.traderBalances(trader2, REP)
        ]);
        let orders = await dex.getOrders(REP, SIDE.BUY);
        assert(orders[0].filled === web3.utils.toWei('5'));
        assert(balances[0].toString() === web3.utils.toWei('150'));
        assert(balances[1].toString()=== web3.utils.toWei('5'));
        assert(balances[2].toString() === web3.utils.toWei('50'));
        assert(balances[3].toString()=== web3.utils.toWei('95'));

        /*Now if another limit order is created, and the first one is completely filled, 
        then first one should pop off the array*/
        await dex.createLimitOrder(REP, 9, web3.utils.toWei('10'), SIDE.BUY, {from:trader1});
        await dex.createMarketOrder(REP, web3.utils.toWei('5'),  SIDE.SELL, {from: trader2});
        orders = await dex.getOrders(REP, SIDE.BUY);
        balances = await Promise.all([
            dex.traderBalances(trader1, DAI),
            dex.traderBalances(trader1, REP),
            dex.traderBalances(trader2, DAI),
            dex.traderBalances(trader2, REP)
        ]);
        assert(orders.length === 1);
        assert(orders[0].filled === web3.utils.toWei('0'));
        assert(orders[0].price === '9');
        assert(balances[0].toString() === web3.utils.toWei('100'));
        assert(balances[1].toString()=== web3.utils.toWei('10'));
        assert(balances[2].toString() === web3.utils.toWei('100'));
        assert(balances[3].toString()=== web3.utils.toWei('90'));

    });

    it('Do not create market sell order if token balance is low', async() => {
        await expectRevert(
            dex.createMarketOrder(REP, web3.utils.toWei('10'), SIDE.SELL, {from: trader1}),
            "Insufficient token balance"
        );
    });

    it('Do not create market order if token does not exist', async() => {
        await expectRevert(
            dex.createMarketOrder(web3.utils.fromAscii('Token'), web3.utils.toWei('10'), SIDE.SELL, {from: trader1}),
            "This token doesn't exist"
        );
    }); 

    it('Do not create market order if token traded is DAI', async() =>{
        await dex.deposit(web3.utils.toWei('100'), DAI, {from: trader1});
        await expectRevert(
            dex.createMarketOrder(DAI, web3.utils.toWei('10'), SIDE.BUY, {from: trader1}),
            "DAI not tradable"
        );
    });

    it('Do not create market buy order if DAI not enough', async() =>{
        await dex.deposit(web3.utils.toWei('10'), REP, {from: trader1});
        await dex.deposit(web3.utils.toWei('10'), DAI, {from: trader2});
        await dex.createLimitOrder(REP, 10, web3.utils.toWei('10'), SIDE.SELL, {from: trader1});
        await expectRevert(
            dex.createMarketOrder(REP, web3.utils.toWei('10'), SIDE.BUY, {from: trader2}),
            "DAI balance insufficient"
        );
    });


    

});
 