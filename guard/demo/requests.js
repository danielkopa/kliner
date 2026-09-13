// The same shapes the test suite uses, frozen for the demo page.
export const REQUESTS = {
  "unlimitedApprove": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "data": "0x095ea7b3000000000000000000000000badc0ffee0ddf00d1234567890abcdef12345678ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }
    ]
  },
  "boundedApprove": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "data": "0x095ea7b30000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d0000000000000000000000000000000000000000000000000000000005f5e100"
      }
    ]
  },
  "revokeApprove": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "data": "0x095ea7b30000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d0000000000000000000000000000000000000000000000000000000000000000"
      }
    ]
  },
  "approveAll": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0x3333333333333333333333333333333333333333",
        "data": "0xa22cb465000000000000000000000000badc0ffee0ddf00d1234567890abcdef123456780000000000000000000000000000000000000000000000000000000000000001"
      }
    ]
  },
  "revokeAll": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0x3333333333333333333333333333333333333333",
        "data": "0xa22cb4650000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d0000000000000000000000000000000000000000000000000000000000000000"
      }
    ]
  },
  "permit2Approve": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0x000000000022d473030f116ddee9f6b43ac78ba3",
        "data": "0x87517c45000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000badc0ffee0ddf00d1234567890abcdef12345678000000000000000000000000ffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000ffffffffffff"
      }
    ]
  },
  "plainSend": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x1bc16d674ec80000",
        "to": "0x5555555555555555555555555555555555555555"
      }
    ]
  },
  "transfer": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "data": "0xa9059cbb00000000000000000000000055555555555555555555555555555555555555550000000000000000000000000000000000000000000000000000000002faf080"
      }
    ]
  },
  "pullFromYou": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "data": "0x23b872dd0000000000000000000000001111111111111111111111111111111111111111000000000000000000000000badc0ffee0ddf00d1234567890abcdef123456780000000000000000000000000000000000000000000000000000000035a4e900"
      }
    ]
  },
  "bundle": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
        "data": "0xac9650d80000000000000000000000000000000000000000000000000000000000000020"
      }
    ]
  },
  "unknownCall": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0xbadc0ffee0ddf00d1234567890abcdef12345678",
        "data": "0xdeadbeef0000000000000000000000000000000000000000000000000000000000000000"
      }
    ]
  },
  "ownership": {
    "method": "eth_sendTransaction",
    "params": [
      {
        "from": "0x1111111111111111111111111111111111111111",
        "value": "0x0",
        "to": "0x3333333333333333333333333333333333333333",
        "data": "0xf2fde38b000000000000000000000000badc0ffee0ddf00d1234567890abcdef12345678"
      }
    ]
  },
  "permitUnlimited": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"Permit\",\"domain\":{\"name\":\"USD Coin\",\"version\":\"2\",\"chainId\":1,\"verifyingContract\":\"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48\"},\"types\":{\"Permit\":[{\"name\":\"owner\",\"type\":\"address\"},{\"name\":\"spender\",\"type\":\"address\"},{\"name\":\"value\",\"type\":\"uint256\"},{\"name\":\"nonce\",\"type\":\"uint256\"},{\"name\":\"deadline\",\"type\":\"uint256\"}]},\"message\":{\"owner\":\"0x1111111111111111111111111111111111111111\",\"spender\":\"0xbadc0ffee0ddf00d1234567890abcdef12345678\",\"value\":\"115792089237316195423570985008687907853269984665640564039457584007913129639935\",\"nonce\":\"3\",\"deadline\":\"99999999999\"}}"
    ]
  },
  "permitBounded": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"Permit\",\"domain\":{\"name\":\"USD Coin\",\"version\":\"2\",\"chainId\":1,\"verifyingContract\":\"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48\"},\"types\":{\"Permit\":[]},\"message\":{\"owner\":\"0x1111111111111111111111111111111111111111\",\"spender\":\"0x7a250d5630b4cf539739df2c5dacb4c659f2488d\",\"value\":\"250000000\",\"nonce\":\"1\",\"deadline\":\"1789330031\"}}"
    ]
  },
  "permit2Single": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"PermitSingle\",\"domain\":{\"name\":\"Permit2\",\"chainId\":1,\"verifyingContract\":\"0x000000000022d473030f116ddee9f6b43ac78ba3\"},\"types\":{\"PermitSingle\":[]},\"message\":{\"details\":{\"token\":\"0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2\",\"amount\":\"1461501637330902918203684832716283019655932542975\",\"expiration\":\"281474976710655\",\"nonce\":\"0\"},\"spender\":\"0xbadc0ffee0ddf00d1234567890abcdef12345678\",\"sigDeadline\":\"281474976710655\"}}"
    ]
  },
  "permit2Batch": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"PermitBatch\",\"domain\":{\"name\":\"Permit2\",\"chainId\":1,\"verifyingContract\":\"0x000000000022d473030f116ddee9f6b43ac78ba3\"},\"types\":{\"PermitBatch\":[]},\"message\":{\"details\":[{\"token\":\"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48\",\"amount\":\"1461501637330902918203684832716283019655932542975\",\"expiration\":\"281474976710655\",\"nonce\":\"0\"},{\"token\":\"0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2\",\"amount\":\"1461501637330902918203684832716283019655932542975\",\"expiration\":\"281474976710655\",\"nonce\":\"0\"},{\"token\":\"0x3333333333333333333333333333333333333333\",\"amount\":\"1000\",\"expiration\":\"1900000000\",\"nonce\":\"0\"}],\"spender\":\"0xbadc0ffee0ddf00d1234567890abcdef12345678\",\"sigDeadline\":\"281474976710655\"}}"
    ]
  },
  "orderForNothing": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"OrderComponents\",\"domain\":{\"name\":\"Seaport\",\"version\":\"1.6\",\"chainId\":1,\"verifyingContract\":\"0x0000000000000068f116a894984e2db1123eb395\"},\"types\":{\"OrderComponents\":[]},\"message\":{\"offerer\":\"0x1111111111111111111111111111111111111111\",\"offer\":[{\"itemType\":2,\"token\":\"0x3333333333333333333333333333333333333333\",\"identifierOrCriteria\":\"88\",\"startAmount\":\"1\",\"endAmount\":\"1\"}],\"consideration\":[{\"itemType\":0,\"token\":\"0x0000000000000000000000000000000000000000\",\"identifierOrCriteria\":\"0\",\"startAmount\":\"0\",\"endAmount\":\"0\",\"recipient\":\"0x1111111111111111111111111111111111111111\"}],\"endTime\":\"99999999999\"}}"
    ]
  },
  "orderWildcard": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"OrderComponents\",\"domain\":{\"name\":\"Seaport\",\"version\":\"1.6\",\"chainId\":1,\"verifyingContract\":\"0x0000000000000068f116a894984e2db1123eb395\"},\"types\":{\"OrderComponents\":[]},\"message\":{\"offerer\":\"0x1111111111111111111111111111111111111111\",\"offer\":[{\"itemType\":4,\"token\":\"0x3333333333333333333333333333333333333333\",\"identifierOrCriteria\":\"0\",\"startAmount\":\"1\",\"endAmount\":\"1\"}],\"consideration\":[{\"itemType\":0,\"token\":\"0x0000000000000000000000000000000000000000\",\"identifierOrCriteria\":\"0\",\"startAmount\":\"1\",\"endAmount\":\"1\",\"recipient\":\"0x1111111111111111111111111111111111111111\"}],\"endTime\":\"99999999999\"}}"
    ]
  },
  "orderNormal": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"OrderComponents\",\"domain\":{\"name\":\"Seaport\",\"version\":\"1.6\",\"chainId\":1,\"verifyingContract\":\"0x0000000000000068f116a894984e2db1123eb395\"},\"types\":{\"OrderComponents\":[]},\"message\":{\"offerer\":\"0x1111111111111111111111111111111111111111\",\"offer\":[{\"itemType\":2,\"token\":\"0x3333333333333333333333333333333333333333\",\"identifierOrCriteria\":\"88\",\"startAmount\":\"1\",\"endAmount\":\"1\"}],\"consideration\":[{\"itemType\":0,\"token\":\"0x0000000000000000000000000000000000000000\",\"identifierOrCriteria\":\"0\",\"startAmount\":\"3000000000000000000\",\"endAmount\":\"3000000000000000000\",\"recipient\":\"0x1111111111111111111111111111111111111111\"},{\"itemType\":0,\"token\":\"0x0000000000000000000000000000000000000000\",\"identifierOrCriteria\":\"0\",\"startAmount\":\"75000000000000000\",\"endAmount\":\"75000000000000000\",\"recipient\":\"0x7a250d5630b4cf539739df2c5dacb4c659f2488d\"}],\"endTime\":\"1789414631\"}}"
    ]
  },
  "wrongChainPermit": {
    "method": "eth_signTypedData_v4",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "{\"primaryType\":\"Permit\",\"domain\":{\"name\":\"USD Coin\",\"chainId\":137,\"verifyingContract\":\"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48\"},\"types\":{\"Permit\":[]},\"message\":{\"owner\":\"0x1111111111111111111111111111111111111111\",\"spender\":\"0xbadc0ffee0ddf00d1234567890abcdef12345678\",\"value\":\"115792089237316195423570985008687907853269984665640564039457584007913129639935\",\"nonce\":\"0\",\"deadline\":\"99999999999\"}}"
    ]
  },
  "blindSign": {
    "method": "eth_sign",
    "params": [
      "0x1111111111111111111111111111111111111111",
      "0xabababababababababababababababababababababababababababababababab"
    ]
  },
  "loginMessage": {
    "method": "personal_sign",
    "params": [
      "0x6578616d706c652e636f6d2077616e747320796f7520746f207369676e20696e207769746820796f757220457468657265756d206163636f756e742e",
      "0x1111111111111111111111111111111111111111"
    ]
  },
  "structuredMessage": {
    "method": "personal_sign",
    "params": [
      "0x7b227370656e646572223a22307862616463306666656530646466303064313233343536373839306162636465663132333435363738222c2276616c7565223a22756e6c696d69746564227d",
      "0x1111111111111111111111111111111111111111"
    ]
  },
  "binaryMessage": {
    "method": "personal_sign",
    "params": [
      "0xfffefdfc",
      "0x1111111111111111111111111111111111111111"
    ]
  }
};
