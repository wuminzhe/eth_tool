require "eth_tool/version"
require 'bip44'
require 'ethereum.rb'
require 'eth'
require 'bigdecimal'

module EthTool

  def self.rpc=(url)
    @@rpc = Ethereum::HttpClient.new(url)
  end

  def self.rpc
    @@rpc
  end

  def self.fee(gas_limit, gas_price)
    BigDecimal(gas_limit) * BigDecimal(gas_price) / 10**18.to_f
  end

  class << self
    attr_accessor :logger
  end

  ############################################################################
 

  def self.get_token_balance(address, token_contract_address, token_decimals)
    data = '0x70a08231' + padding(address) # Ethereum::Function.calc_id('balanceOf(address)') # 70a08231
  
    result = @@rpc.eth_call({to: token_contract_address, data: data})['result'].to_i(16)
    BigDecimal(result) / BigDecimal(10**token_decimals)
  end
  
  def self.get_eth_balance(address)
    result = @@rpc.eth_get_balance(address)['result'].to_i(16)
    BigDecimal(result) / BigDecimal(10**18)
  end

  # value: 实际的eth数量，gas_limit 和 gas_price都是十进制
  def self.generate_raw_transaction(private_key, value, data, gas_limit, gas_price = nil, to = nil, nonce = nil)
    key = ::Eth::Key.new priv: private_key
    address = key.address
  
    gas_price_in_dec = gas_price.nil? ? @@rpc.eth_gas_price["result"].to_i(16) : gas_price
    nonce = nonce.nil? ? @@rpc.eth_get_transaction_count(address, 'pending')["result"].to_i(16) : nonce

    args = {
      from: address,
      value: 0,
      data: '0x0',
      nonce: nonce,
      gas_limit: gas_limit,
      gas_price: gas_price_in_dec
    }

    args[:value] = (value * 10**18).to_i if value
    args[:data] = data if data
    args[:to] = to if to
    tx = Eth::Tx.new(args)
    tx.sign key
    tx.hex
  end

  def self.estimate_gas(to, data)
    @@rpc.eth_estimate_gas({to: to, data: data})["result"].to_i(16)
  end

  def self.build_airdrop_data(token_contract_address, addresses, values)
    data = "0xad8733ca"
    data = data + padding(token_contract_address)
    data = data + "0000000000000000000000000000000000000000000000000000000000000060"
    data = data + "0000000000000000000000000000000000000000000000000000000000001840"
    data = data + "00000000000000000000000000000000000000000000000000000000000000be"
    addresses.each do |address|
      data = data + padding(address.downcase)
    end
    data = data + "00000000000000000000000000000000000000000000000000000000000000be"
    values.each do |value|
      data = data + padding(value.to_i.to_s(16))
    end
    return data
  end

  def self.airdrop(private_key, airdrop_contract_address, token_contract_address, addresses, values, gas_limit, gas_price)
    data = build_airdrop_data(token_contract_address, addresses, values)

    rawtx = generate_raw_transaction(private_key, 0, data, gas_limit, gas_price, airdrop_contract_address)
    
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  def self.transfer_token(private_key, token_contract_address, token_decimals, amount, gas_limit, gas_price, to, nonce=nil)
    if amount < (1.0/10**token_decimals)
      logger.info "转账金额不能小于精度最小单位(#{token_contract_address}, #{token_decimals})"
      return
    end

    # 生成raw transaction
    amount_in_wei = (amount * (10**token_decimals)).to_i
    data = '0xa9059cbb' + padding(to) + padding(dec_to_hex(amount_in_wei)) # Ethereum::Function.calc_id('transfer(address,uint256)') # a9059cbb
    rawtx = generate_raw_transaction(private_key, 0, data, gas_limit, gas_price, token_contract_address, nonce)
    
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  def self.transfer_eth(private_key, amount, gas_limit, gas_price, to)
    if amount < (1.0/10**18)
      logger.info "转账金额不能小于以太坊最小单位"
      return 
    end
    rawtx = generate_raw_transaction(private_key, amount, nil, gas_limit, gas_price, to)
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  # sweep
  def self.sweep_token(private_key, token_contract_address, token_decimals, to, gas_limit=60000, gas_price=5_000_000_000)
    address = ::Eth::Key.new(priv: private_key).address
    token_balance = get_token_balance(address, token_contract_address, token_decimals)
    return if token_balance == 0
    transfer_token(private_key, token_contract_address, token_decimals, token_balance, gas_limit, gas_price, to)
  end

  def self.sweep_eth(private_key, to, gas_limit=60000, gas_price=5_000_000_000)
    address = ::Eth::Key.new(priv: private_key).address
    eth_balance = get_eth_balance(address)
    # 转eth不能都转，要留一点作为gas费用
    keep = BigDecimal(gas_limit) * BigDecimal(gas_price) / 10**18
    amount = eth_balance - keep
    return if amount <= 0
    transfer_eth(private_key, amount, gas_limit, gas_price, to)
  end

  # 目标地址上需要填充满这么多eth
  # amount = BigDecimal(gas_limit) * BigDecimal(gas_price) / 10**18
  def self.fill_eth(private_key, to, amount, gas_limit=60000, gas_price=5_000_000_000)
    # 目标地址上现有eth
    eth_balance = get_eth_balance(to)

    return unless eth_balance < amount # 如果有足够多的eth，就直接返回
    
    transfer_eth(private_key, (amount-eth_balance), gas_limit, gas_price, to)
  end

  def self.tx_replace(private_key, txhash, gas_price)
    tx = @@rpc.eth_get_transaction_by_hash(txhash)["result"]
    return if tx.nil?
  
    value = BigDecimal(tx["value"].to_i(16)) / 10**18
    data = tx["input"]
    gas_limit = tx["gas"].to_i(16)
    gas_price = gas_price
    to = tx["to"]
    nonce = tx["nonce"].to_i(16)

    rawtx = generate_raw_transaction(private_key, value, data, gas_limit, gas_price, to, nonce)
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  def self.get_private_key_from_keystore(dir, address, passphrase)
    path = File.join(dir, '*')
    Dir[path].each do |file|
      if file.end_with?(address[2..-1])
        key = ::Eth::Key.decrypt(File.read(file), passphrase)
        return key.private_key.to_hex
      end
    end
  end

  def self.generate_addresses_from_xprv(xprv, amount)
    result = []
    wallet = Bip44::Wallet.from_xprv(xprv)
    amount.times do |i|
      sub_wallet = wallet.sub_wallet("m/#{i}")
      result << sub_wallet.ethereum_address
    end
    result
  end

  def self.get_private_key_from_xprv(xprv, index)
    wallet = Bip44::Wallet.from_xprv(xprv)
    sub_wallet = wallet.sub_wallet("m/#{index}")
    return sub_wallet.private_key, sub_wallet.ethereum_address
  end

  def self.wait_for_miner(txhash, timeout: 1200, step: 20)
    start_time = Time.now
    loop do
      raise Timeout::Error if ((Time.now - start_time) > timeout)
      return true if mined?(txhash)
      sleep step
    end
  end

  def self.mined?(txhash)
    tx = @@rpc.eth_get_transaction_by_hash(txhash)["result"]
    tx and (not tx['blockNumber'].nil?)
  end

  def self.confirmed?(txhash, number)
    tx = @@rpc.eth_get_transaction_by_hash(txhash)["result"]

    return false unless (tx and (not tx['blockNumber'].nil?))

    block_number = tx['blockNumber'].to_i(16)
    current_block_number = @@rpc.eth_block_number["result"].to_i(16)
    confirmations = current_block_number - block_number

    confirmations >= number
  end

  def self.confirmations(txhash)
    tx = @@rpc.eth_get_transaction_by_hash(txhash)["result"]

    return 0 unless (tx and (not tx['blockNumber'].nil?))

    block_number = tx['blockNumber'].to_i(16)
    current_block_number = @@rpc.eth_block_number["result"].to_i(16)
    current_block_number - block_number
  end

  def self.token_transfer_success?(txhash)
    tx = @@rpc.eth_get_transaction_by_hash(txhash)["result"]
    return false unless (tx and (not tx['blockNumber'].nil?))

    receipt = @@rpc.eth_get_transaction_receipt(txhash)["result"]
    return false unless receipt

    return false if (receipt['status'] && receipt['status'] == '0x0')
  end

  # helper methods #########################################################

  def self.dec_to_hex(value)
    '0x'+value.to_s(16)
  end

  def self.padding(str)
    if str =~ /^0x[a-f0-9]*/
      str = str[2 .. str.length-1]
    end
    str.rjust(64, '0')
  end
  
end
