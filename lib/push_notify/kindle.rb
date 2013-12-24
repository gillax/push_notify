module PushNotify
  class Kindle
    # @param [String] client_id
    # @param [String] client_secret
    def initialize(client_id, client_secret)
      @client_id = client_id
      @client_secret = client_secret
    end

    # @return [String] access token
    # @see https://developer.amazon.com/sdk/adm/token.html
    def get_access_token
      @access_token = nil

      uri = ::URI.parse('https://api.amazon.com/auth/O2/token')

      params = {
        grant_type:    'client_credentials',
        scope:         'messaging:push',
        client_id:     @client_id,
        client_secret: @client_secret,
      }
      res = ::Net::HTTP.post_form(uri, params)
      body = ::JSON.parse(res.body)
      p body.inspect

      if res.code == '200'
        @access_token = body["access_token"]
      else
        raise "#{res.code} : #{body["reason"]}"
      end
      @access_token
    end

    # @param [String] registration_id
    # @param [hash] payload
    # @return [String] new registration_id
    # @return [nil] If registration_id did not change.
    #
    # @see https://developer.amazon.com/sdk/adm/sending-message.html
    def send(registration_id, payload)
      new_registration_id = nil

      uri = ::URI.parse("https://api.amazon.com/messaging/registrations/#{registration_id}/messages")

      headers = {
        "Authorization"       => "Bearer #{@access_token}",
        "Content-Type"        => "application/json",
        "X-Amzn-Type-Version" => "com.amazon.device.messaging.ADMMessage@1.0",
        "Accept"              => "application/json",
        "X-Amzn-Accept-Type"  => "com.amazon.device.messaging.ADMSendResult@1.0",
      }
      # :data => メッセージとして送信する項目JSON形式(6KB以下データ量である必要あり)
      # :consolidationKey => メッセージの内容をグルーピングできる前回同じものを送った場合には上書きされる。(64文字以内)
      # :expiresAfter => ADMサーバーがメッセージキューに保存する期間（最小値:60秒[1分] 最大値:2678400秒[31日] デフォルト:604800[1週間]
      body = {
        "data" => payload.to_json, 
        "consolidationKey" => 'ADMMessage',
        "expiresAfter" => 604800,
      }

      http = ::Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = !!(uri.port == 443)
      res = http.post(uri.path, body.to_json, headers)
      body = ::JSON.parse(res.body)
      p body.inspect

      if res.code == '200'
        if body.key?("registrationID")
          reg_id = body["registrationID"]
          if registration_id != reg_id
            new_registration_id = reg_id
          end
        end

      elsif res.code == '401'
        # maybe access token has expired. u can retry until 3times.
        @retry_count = 0 if !@retry_count
        if @retry_count < 3
          @retry_count += 1
          get_access_token
          send(registration_id, payload)
        else
          raise "#{res.code} : #{body['reason']}"
        end
      else
        raise "#{res.code} : #{body['reason']}"
      end

      new_registration_id
    end
  end
end

