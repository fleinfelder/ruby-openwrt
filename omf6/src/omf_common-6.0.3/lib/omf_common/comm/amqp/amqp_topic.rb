# Copyright (c) 2012 National ICT Australia Limited (NICTA).
# This software may be used and distributed solely under the terms of the MIT license (License).
# You should find a copy of the License in LICENSE.TXT or at http://opensource.org/licenses/MIT.
# By downloading or using this software you accept the terms and the liability disclaimer in the License.



module OmfCommon
  class Comm
    class AMQP
      class Topic < OmfCommon::Comm::Topic

        def to_s
          "AMQP::Topic<#{id}>"
        end

        def address
          @address
        end

        # Call 'block' when topic is subscribed to underlying messaging
        # infrastructure.
        #
        def on_subscribed(&block)
          return unless block

          call_now = false
          @lock.synchronize do
            if @subscribed
              call_now = true
            else
              @on_subscribed_handlers << block
            end
          end
          if call_now
            after(0, &block)
          end
        end


        private

        def initialize(id, opts = {})
          unless @communicator = opts.delete(:communicator)
            raise "Missing :communicator option"
          end
          super
          @address = opts[:address]
          @lock = Monitor.new
          @subscribed = false
          @on_subscribed_handlers = []

          # @communicator.on_reconnect(self) do
            # info "Resubscribe '#{self}'"
            # _init_amqp
          # end
          _init_amqp
        end

        def _init_amqp()
          channel = @communicator.channel
          @exchange = channel.topic(id, :auto_delete => true)
          # @exchange.on_connection_interruption do |ex|
            # warn "Exchange #{ex.name} detected connection interruption"
            # @exchange = nil
          # end
          channel.queue("", :exclusive => true) do |queue|
            #puts "QQ1(#{id}): #{queue}"
            queue.bind(@exchange)
            queue.subscribe do |headers, payload|
              #puts "===(#{id}) Incoming message '#{headers.content_type}'"
              debug "Received message on #{@address}"
              Message.parse(payload, headers.content_type) do |msg|
                #puts "---(#{id}) Parsed message '#{msg}'"
                on_incoming_message(msg)
              end
            end
            debug "Subscribed to '#@id'"
            # Call all accumulated on_subscribed handlers
            @lock.synchronize do
              @subscribed = true
              @on_subscribed_handlers.each do |block|
                after(0, &block)
              end
              @on_subscribed_handlers = nil
            end
          end
        end

        def _send_message(msg, block = nil)
          super
          content_type, content = msg.marshall(self)
          debug "(#{id}) Send message (#{content_type}) #{msg.inspect}"
          if @exchange
            @exchange.publish(content, content_type: content_type, message_id: msg.mid)
          else
            warn "Unavailable AMQP channel. Dropping message '#{msg}'"
          end
        end
      end # class
    end # module
  end # module
end # module
