#!/usr/bin/env ruby
# 既存の reviewSubmission を一覧し、READY_FOR_REVIEW 前の(未提出)ものを削除する。
# fastlane submit の失敗で残ったダングリング submission が 409 を引き起こすため。
require "spaceship"

key_id    = ENV.fetch("ASC_KEY_ID")
issuer_id = ENV.fetch("ASC_ISSUER_ID")
key_path  = ENV.fetch("ASC_KEY_FILEPATH")
app_id    = "6782291563"

token = Spaceship::ConnectAPI::Token.create(
  key_id: key_id,
  issuer_id: issuer_id,
  filepath: key_path
)
Spaceship::ConnectAPI.token = token

app = Spaceship::ConnectAPI::App.get(app_id: app_id)
puts "App: #{app.name} (#{app.bundle_id})"

# contentRightsDeclaration を確認
begin
  detail = Spaceship::ConnectAPI.get_app(app_id: app_id, includes: nil)
  puts "contentRightsDeclaration(app attr): #{app.content_rights_declaration rescue 'n/a'}"
rescue => e
  puts "app detail fetch: #{e.message}"
end

subs = Spaceship::ConnectAPI.get_review_submissions(app_id: app_id).to_a
puts "review submissions: #{subs.size}"
subs.each do |s|
  puts "  id=#{s.id} state=#{s.state} platform=#{s.platform}"
  items = (Spaceship::ConnectAPI.get_review_submission_items(review_submission_id: s.id).to_a rescue [])
  puts "    items=#{items.size}"
  # 未提出(下書き相当)の submission を削除
  if %w[READY_FOR_REVIEW].include?(s.state)
    puts "    -> READY_FOR_REVIEW (already submitted) — skip delete"
  elsif %w[COMPLETE COMPLETED].include?(s.state)
    puts "    -> complete — skip"
  else
    begin
      Spaceship::ConnectAPI.delete_review_submission(review_submission_id: s.id)
      puts "    -> DELETED"
    rescue => e
      puts "    -> delete failed: #{e.message}"
    end
  end
end
puts "done"
