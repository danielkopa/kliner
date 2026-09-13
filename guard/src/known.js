// A small table of tokens, so an amount can be written the way a person reads it.
//
// Kliner Guard never goes to the network — that is the whole point — so it
// cannot ask a token how many decimals it has. This table covers the tokens
// that drainers actually target. A token that is missing is not a failure: the
// amount is then shown in its raw units and said to be raw, which is honest,
// and "everything, forever" does not need decimals at all.

export const TOKENS = {
    // Ethereum
    '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48': { symbol: 'USDC', decimals: 6 },
    '0xdac17f958d2ee523a2206206994597c13d831ec7': { symbol: 'USDT', decimals: 6 },
    '0x6b175474e89094c44da98b954eedeac495271d0f': { symbol: 'DAI', decimals: 18 },
    '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2': { symbol: 'WETH', decimals: 18 },
    '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599': { symbol: 'WBTC', decimals: 8 },
    '0xae7ab96520de3a18e5e111b5eaab095312d7fe84': { symbol: 'stETH', decimals: 18 },
    '0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0': { symbol: 'wstETH', decimals: 18 },
    '0x514910771af9ca656af840dff83e8264ecf986ca': { symbol: 'LINK', decimals: 18 },
    '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984': { symbol: 'UNI', decimals: 18 },
    '0x6982508145454ce325ddbe47a25d4ec3d2311933': { symbol: 'PEPE', decimals: 18 },
    '0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce': { symbol: 'SHIB', decimals: 18 },
    '0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9': { symbol: 'AAVE', decimals: 18 },
    '0x4d224452801aced8b2f0aebe155379bb5d594381': { symbol: 'APE', decimals: 18 },
    '0xd533a949740bb3306d119cc777fa900ba034cd52': { symbol: 'CRV', decimals: 18 },

    // Base
    '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913': { symbol: 'USDC', decimals: 6 },
    '0x4200000000000000000000000000000000000006': { symbol: 'WETH', decimals: 18 },

    // Arbitrum
    '0xaf88d065e77c8cc2239327c5edb3a432268e5831': { symbol: 'USDC', decimals: 6 },
    '0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9': { symbol: 'USDT', decimals: 6 },
    '0x82af49447d8a07e3bd95bd0d56f35241523fbab1': { symbol: 'WETH', decimals: 18 },
    '0x912ce59144191c1204e64559fe8253a0e49e6548': { symbol: 'ARB', decimals: 18 },

    // Polygon
    '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270': { symbol: 'WPOL', decimals: 18 },
    '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359': { symbol: 'USDC', decimals: 6 },
};

// Contracts worth naming when they show up as the thing being called.
export const CONTRACTS = {
    '0x000000000022d473030f116ddee9f6b43ac78ba3': 'Permit2',
    '0x00000000006c3852cbef3e08e8df289169ede581': 'Seaport 1.1',
    '0x00000000000001ad428e4906ae43d8f9852d0dd6': 'Seaport 1.4',
    '0x0000000000000068f116a894984e2db1123eb395': 'Seaport 1.6',
    '0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad': 'the Uniswap Universal Router',
    '0x7a250d5630b4cf539739df2c5dacb4c659f2488d': 'the Uniswap V2 Router',
    '0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45': 'the Uniswap V3 Router',
    '0x1111111254eeb25477b68fb85ed929f73a960582': 'the 1inch Router',
    '0x000000000000ad05ccc4f10045630fb830b95127': 'Blur',
};

// What the chain's own currency is called, so an amount with no token can
// still be written properly.
export const CURRENCY = {
    1: 'ETH', 8453: 'ETH', 42161: 'ETH', 10: 'ETH', 324: 'ETH', 534352: 'ETH', 59144: 'ETH',
    137: 'POL', 56: 'BNB', 43114: 'AVAX', 100: 'xDAI', 250: 'FTM',
};

export function currencyFor(chainId) {
    return CURRENCY[Number(chainId)] || 'the chain currency';
}

export function tokenFor(address) {
    return TOKENS[(address || '').toLowerCase()] || null;
}

export function contractName(address) {
    return CONTRACTS[(address || '').toLowerCase()] || null;
}
