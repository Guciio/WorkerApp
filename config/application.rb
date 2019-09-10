require_relative 'boot'

require 'rails/all'
require 'aws-sdk-sqs'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WorkerApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    config.after_initialize do

      loop do
        sqs = Aws::SQS::Client.new(region: "us-west-2",
            access_key_id: Rails.application.credentials.aws[:access_key_id],
            secret_access_key: Rails.application.credentials.aws[:secret_access_key])

        receive_queue_name = "awsprojectqueue.fifo"
        receive_queue_url = sqs.get_queue_url(queue_name: receive_queue_name).queue_url
        poller = Aws::SQS::QueuePoller.new(receive_queue_url)

        poller_stats = poller.poll({
                                       max_number_of_messages: 5,
                                       idle_timeout: 10 # Stop polling after 60 seconds of no more messages available (polls indefinitely by default).
                                   }) do |messages|
          messages.each do |message|
            puts "Message body: #{message.body}"

            if message.body[0] == 'R'
              photo_key = message.body[2..].to_s
              s3 = Aws::S3::Client.new(region: 'us-west-2')
              @temp_file_location = "./tmp/#{photo_key}.png"
              resp = s3.get_object(bucket:'awsprojectbuckett', key:photo_key)
              File.open(@temp_file_location, 'wb') { |file| file.write(resp.body.read) }

              image = MiniMagick::Image.new(@temp_file_location)

              image.combine_options do |img|
                img.rotate "-90"
              end

              s3 = Aws::S3::Resource.new(region: 'us-west-2')
              obj = s3.bucket('awsprojectbuckett').object(photo_key)
              obj.upload_file(@temp_file_location, acl: 'public-read')

              puts "Photo saved"
             end
          end
        end
        # Note: If poller.poll is successful, all received messages are automatically deleted from the queue.

        puts "Poller stats:"
        puts "  Polling started at: #{poller_stats.polling_started_at}"
        puts "  Polling stopped at: #{poller_stats.polling_stopped_at}"
        puts "  Last message received at: #{poller_stats.last_message_received_at}"
        puts "  Number of polling requests: #{poller_stats.request_count}"
        puts "  Number of received messages: #{poller_stats.received_message_count}"
      end
    end
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end


