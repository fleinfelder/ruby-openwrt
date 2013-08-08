# Copyright (c) 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.

require 'blather/client/dsl'

require 'omf_common/comm/xmpp/xmpp_mp'
require 'omf_common/comm/xmpp/topic'
require 'uri'
require 'socket'

module OmfCommon
class Comm
  class XMPP
    class Communicator < OmfCommon::Comm
      include Blather::DSL

      attr_accessor :published_messages, :normal_shutdown_mode, :retry_counter

      HOST_PREFIX = 'pubsub'

      PUBSUB_CONFIGURE = Blather::Stanza::X.new({
        :type => :submit,
        :fields => [
          { :var => "FORM_TYPE", :type => 'hidden', :value => "http://jabber.org/protocol/pubsub#node_config" },
          { :var => "pubsub#persist_items", :value => "0" },
          { :var => "pubsub#purge_offline", :value => "1" },
          { :var => "pubsub#send_last_published_item", :value => "never" },
          { :var => "pubsub#notify_retract",  :value => "0" },
          { :var => "pubsub#publish_model", :value => "open" }]
      })

      def conn_info
        { proto: :xmpp, user: jid.node, domain: jid.domain }
      end

      # Capture system :INT & :TERM signal
      def on_interrupted(&block)
        @cbks[:interpreted] << block
      end

      def on_connected(&block)
        @cbks[:connected] << block
      end

      # Set up XMPP options and start the Eventmachine, connect to XMPP server
      #
      def init(opts = {})
        @pubsub_host = opts[:pubsub_domain]
        if opts[:url]
          url = URI(opts[:url])
          username, password, server = url.user, url.password, url.host
        else
          username, password, server = opts[:username], opts[:password], opts[:server]
        end

        random_name = "#{Socket.gethostname}-#{Process.pid}"
        username ||= random_name
        password ||= random_name

        raise ArgumentError, "Username cannot be nil when connect to XMPP" if username.nil?
        raise ArgumentError, "Password cannot be nil when connect to XMPP" if password.nil?
        raise ArgumentError, "Server cannot be nil when connect to XMPP" if server.nil?

        @retry_counter = 0
        @normal_shutdown_mode = false

        connect(username, password, server)

        when_ready do
          @cbks[:connected].each { |cbk| cbk.call(self) }
        end

        disconnected do
          unless normal_shutdown_mode
            unless retry_counter > 0
              @retry_counter += 1
              client.connect
            else
              error "Authentication failed."
              OmfCommon.eventloop.stop
            end
          else
            shutdown
          end
        end

        trap(:INT) { @cbks[:interpreted].empty? ? disconnect : @cbks[:interpreted].each { |cbk| cbk.call(self) } }
        trap(:TERM) { @cbks[:interpreted].empty? ? disconnect : @cbks[:interpreted].each { |cbk| cbk.call(self) } }

        super
      end

      # Set up XMPP options and start the Eventmachine, connect to XMPP server
      #
      def connect(username, password, server)
        info "Connecting to '#{server}' ..."
        jid = "#{username}@#{server}"
        client.setup(jid, password)
        client.run
        MPConnection.inject(Time.now.to_f, jid, 'connect') if OmfCommon::Measure.enabled?
      end

      # Shut down XMPP connection
      def disconnect(opts = {})
        # NOTE Do not clean up
        info "Disconnecting ..."
        @normal_shutdown_mode = true
        shutdown
        OmfCommon::DSL::Xmpp::MPConnection.inject(Time.now.to_f, jid, 'disconnect') if OmfCommon::Measure.enabled?
      end

      # Create a new pubsub topic with additional configuration
      #
      # @param [String] topic Pubsub topic name
      def create_topic(topic, opts = {})
        OmfCommon::Comm::XMPP::Topic.create(topic)
      end

      # Delete a pubsub topic
      #
      # @param [String] topic Pubsub topic name
      def delete_topic(topic, &block)
        pubsub.delete(topic, default_host, &callback_logging(__method__, topic, &block))
      end

      # Subscribe to a pubsub topic
      #
      # @param [String] topic Pubsub topic name
      # @param [Hash] opts
      # @option opts [Boolean] :create_if_non_existent create the topic if non-existent, use this option with caution
      def subscribe(topic, opts = {}, &block)
        topic = topic.first if topic.is_a? Array
        OmfCommon::Comm::XMPP::Topic.create(topic, &block)
        MPSubscription.inject(Time.now.to_f, jid, 'join', topic) if OmfCommon::Measure.enabled?
      end

      def _subscribe(topic, &block)
        pubsub.subscribe(topic, nil, default_host, &callback_logging(__method__, topic, &block))
      end

      def _create(topic, &block)
        pubsub.create(topic, default_host, PUBSUB_CONFIGURE, &callback_logging(__method__, topic, &block))
      end

      # Un-subscribe all existing subscriptions from all pubsub topics.
      def unsubscribe
        pubsub.subscriptions(default_host) do |m|
          m[:subscribed] && m[:subscribed].each do |s|
            pubsub.unsubscribe(s[:node], nil, s[:subid], default_host, &callback_logging(__method__, s[:node], s[:subid]))
            MPSubscription.inject(Time.now.to_f, jid, 'leave', s[:node]) if OmfCommon::Measure.enabled?
          end
        end
      end

      def affiliations(&block)
        pubsub.affiliations(default_host, &callback_logging(__method__, &block))
      end

      # Publish to a pubsub topic
      #
      # @param [String] topic Pubsub topic name
      # @param [OmfCommon::Message] message Any XML fragment to be sent as payload
      def publish(topic, message, &block)
        raise StandardError, "Invalid message" unless message.valid?

        message = message.marshall[1] unless message.kind_of? String
        if message.nil?
          debug "Cannot publish empty message, using authentication and not providing a proper cert?"
          return nil
        end

        new_block = proc do |stanza|
          published_messages << OpenSSL::Digest::SHA1.new(message.to_s)
          block.call(stanza) if block
        end

        pubsub.publish(topic, message, default_host, &callback_logging(__method__, topic, &new_block))
        MPPublished.inject(Time.now.to_f, jid, topic, message.to_s.gsub("\n",'')) if OmfCommon::Measure.enabled?
      end

      # Event callback for pubsub topic event(item published)
      #
      def topic_event(additional_guard = nil, &block)
        guard_block = proc do |event|
          passed = !event.delayed? && event.items? && !event.items.first.payload.nil? #&&
            #!published_messages.include?(OpenSSL::Digest::SHA1.new(event.items.first.payload))

          MPReceived.inject(Time.now.to_f, jid, event.node, event.items.first.payload.to_s.gsub("\n",'')) if OmfCommon::Measure.enabled? && passed

          if additional_guard
            passed && additional_guard.call(event)
          else
            passed
          end
        end
        pubsub_event(guard_block, &callback_logging(__method__, &block))
      end

      private

      def initialize(opts = {})
        self.published_messages = []
        @cbks = {connected: [], interpreted: []}
        super
      end

      # Provide a new block wrap to automatically log errors
      def callback_logging(*args, &block)
        m = args.empty? ? "OPERATION" : args.join(" >> ")
        proc do |stanza|
          if stanza.respond_to?(:error?) && stanza.error?
            e_stanza = Blather::StanzaError.import(stanza)
            if [:unexpected_request].include? e_stanza.name
              logger.debug e_stanza
            elsif e_stanza.name == :conflict
              #logger.debug e_stanza
            else
              logger.warn "#{e_stanza} Original: #{e_stanza.original}"
            end
          end
          logger.debug "#{m} SUCCEED" if stanza.respond_to?(:result?) && stanza.result?
          block.call(stanza) if block
        end
      end

      def default_host
        @pubsub_host || "#{HOST_PREFIX}.#{jid.domain}"
      end
    end
  end
end
end
