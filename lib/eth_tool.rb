require "eth_tool/version"
require 'bip44'
require 'ethereum.rb'
require 'eth'

module EthTool
  def self.rpc=(url)
    @@rpc = Ethereum::HttpClient.new(url)
  end

  def self.get_token_balance(address, token_contract_address, token_decimals)
    data = '0x70a08231' + padding(address) # Ethereum::Function.calc_id('balanceOf(address)') # 70a08231
  
    result = @@rpc.eth_call({to: token_contract_address, data: data})['result'].to_i(16)
    result / (10**token_decimals.to_f)
  end
  
  def self.get_eth_balance(address)
    result = @@rpc.eth_get_balance(address)['result'].to_i(16)
    result / (10**18.to_f)
  end

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

  def self.transfer_token(private_key, token_contract_address, token_decimals, amount, gas_limit, gas_price, to)
    # 生成raw transaction
    amount_in_wei = (amount * (10**token_decimals)).to_i
    data = '0xa9059cbb' + padding(to) + padding(dec_to_hex(amount_in_wei)) # Ethereum::Function.calc_id('transfer(address,uint256)') # a9059cbb
    rawtx = generate_raw_transaction(private_key, 0, data, gas_limit, gas_price, token_contract_address)
    
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  def self.transfer_eth(private_key, amount, gas_limit, gas_price, to)
    rawtx = generate_raw_transaction(private_key, amount, nil, gas_limit, gas_price, to)
    @@rpc.eth_send_raw_transaction(rawtx)
  end

  def self.sweep_eth(private_key, to)
    address = ::Eth::Key.new(priv: private_key).address
    eth_balance = get_eth_balance(address)
    gas_limit = 60000
    gas_price = 10_000_000_000
    amount = eth_balance - (gas_limit * gas_price / 10**18.to_f)
    transfer_eth(private_key, amount, gas_limit, gas_price, to)
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


  # helper methods

  def self.dec_to_hex(value)
    '0x'+value.to_s(16)
  end

  def self.padding(str)
    if str =~ /^0x[a-f0-9]*/
      str = str[2 .. str.length-1]
    end
    str.rjust(64, '0')
  end

  def self.wputs(file, text)
    File.open(file, 'a') { |f| f.puts(text) }
  end
  
end
