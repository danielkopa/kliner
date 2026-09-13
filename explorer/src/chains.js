// Chains Kliner reads. Everything here is public and needs no key, because a
// key is a server, and a server is a thing that can be breached or switched
// off. Kliner runs in your browser and talks to the chain directly.

export const CHAINS = {
    ethereum: {
        id: 1,
        name: 'Ethereum',
        symbol: 'ETH',
        currency: 'ether',
        wrapped: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
        rpc: ['https://eth.llamarpc.com', 'https://rpc.ankr.com/eth', 'https://cloudflare-eth.com'],
        explorer: 'https://etherscan.io',
        blockTime: 12,
    },
    base: {
        id: 8453,
        name: 'Base',
        symbol: 'ETH',
        currency: 'ether',
        wrapped: '0x4200000000000000000000000000000000000006',
        rpc: ['https://mainnet.base.org', 'https://base.llamarpc.com'],
        explorer: 'https://basescan.org',
        blockTime: 2,
    },
    arbitrum: {
        id: 42161,
        name: 'Arbitrum',
        symbol: 'ETH',
        currency: 'ether',
        wrapped: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1',
        rpc: ['https://arb1.arbitrum.io/rpc', 'https://arbitrum.llamarpc.com'],
        explorer: 'https://arbiscan.io',
        blockTime: 0.26,
    },
    optimism: {
        id: 10,
        name: 'Optimism',
        symbol: 'ETH',
        currency: 'ether',
        wrapped: '0x4200000000000000000000000000000000000006',
        rpc: ['https://mainnet.optimism.io', 'https://optimism.llamarpc.com'],
        explorer: 'https://optimistic.etherscan.io',
        blockTime: 2,
    },
    polygon: {
        id: 137,
        name: 'Polygon',
        symbol: 'POL',
        currency: 'POL',
        wrapped: '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270',
        rpc: ['https://polygon-rpc.com', 'https://polygon.llamarpc.com'],
        explorer: 'https://polygonscan.com',
        blockTime: 2,
    },
    bnb: {
        id: 56,
        name: 'BNB Chain',
        symbol: 'BNB',
        currency: 'BNB',
        wrapped: '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c',
        rpc: ['https://bsc-dataseed.binance.org', 'https://binance.llamarpc.com'],
        explorer: 'https://bscscan.com',
        blockTime: 3,
    },
};

export const CHAIN_LIST = Object.entries(CHAINS).map(([key, c]) => ({ key, ...c }));

export function chainByKey(key) {
    return CHAINS[key] ? { key, ...CHAINS[key] } : null;
}

export function chainById(id) {
    return CHAIN_LIST.find((c) => c.id === Number(id)) || null;
}

// Bridges worth naming. The shape already tells us a bridge happened; this
// only supplies a nicer word for it. A missing address costs a label, not a
// reading, which is why the list being incomplete is not a problem.
export const BRIDGES = {
    '0x8315177ab297ba92a06054ce80a67ed4dbd7ed3a': 'the Arbitrum bridge',
    '0x99c9fc46f92e8a1c0dec1b1747d010903e884be1': 'the Optimism bridge',
    '0x3154cf16ccdb4c6d922629664174b904d80f2c35': 'the Base bridge',
    '0xa0c68c638235ee32657e8f720a23cec1bfc77c77': 'the Polygon bridge',
    '0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf': 'the Polygon bridge',
    '0x3ee18b2214aff97000d974cf647e7c347e8fa585': 'Wormhole',
    '0x1a44076050125825900e736c501f859c50fe728c': 'LayerZero',
    '0xbd3fa81b58ba92a82136038b25adec7066af3155': 'Circle CCTP',
    '0x0a992d191deec32afe36203ad87d7d289a738f81': 'Circle CCTP',
};
