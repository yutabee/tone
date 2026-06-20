#!/usr/bin/env ruby
# App の contentRightsDeclaration を API で直接 PATCH する。
# ASC Web UI で「いいえ」を設定しても API 属性が空のままで、review submission が
# "missing contentRightsDeclaration" で失敗するため、API で確実に設定する。
require "spaceship"
require "net/http"
require "json"

key_id    = ENV.fetch("ASC_KEY_ID")
issuer_id = ENV.fetch("ASC_ISSUER_ID")
key_path  = ENV.fetch("ASC_KEY_FILEPATH")
app_id    = "6782291563"

token = Spaceship::ConnectAPI::Token.create(key_id: key_id, issuer_id: issuer_id, filepath: key_path)
Spaceship::ConnectAPI.token = token

def req(token, method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
  klass = { get: Net::HTTP::Get, patch: Net::HTTP::Patch }.fetch(method)
  r = klass.new(uri)
  r["Authorization"] = "Bearer #{token.text}"
  r["Content-Type"]  = "application/json"
  r.body = JSON.generate(body) if body
  http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = true
  http.request(r)
end

# 1. 現在値を確認
g = req(token, :get, "apps/#{app_id}?fields[apps]=contentRightsDeclaration")
cur = JSON.parse(g.body).dig("data", "attributes", "contentRightsDeclaration") rescue nil
puts "before: contentRightsDeclaration=#{cur.inspect}"

# 2. PATCH で設定
body = {
  data: {
    type: "apps",
    id: app_id,
    attributes: { contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT" }
  }
}
p = req(token, :patch, "apps/#{app_id}", body)
puts "PATCH status: #{p.code}"
puts p.body unless p.code.to_i.between?(200, 299)

# 3. 再確認
g2 = req(token, :get, "apps/#{app_id}?fields[apps]=contentRightsDeclaration")
after = JSON.parse(g2.body).dig("data", "attributes", "contentRightsDeclaration") rescue nil
puts "after:  contentRightsDeclaration=#{after.inspect}"
