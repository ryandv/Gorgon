require 'gorgon/originator_protocol'
require 'gorgon/configuration'
require 'gorgon/job_state'
require 'gorgon/progress_bar_view'
require 'gorgon/originator_logger'
require 'gorgon/failures_printer'
require 'gorgon/source_tree_syncer'
require 'gorgon/shutdown_manager.rb'

require 'awesome_print'
require 'etc'
require 'socket'

class Originator
  include Configuration

  def initialize
    @configuration = nil
  end

  def originate
    begin
      Signal.trap("INT") { ctrl_c }
      Signal.trap("TERM") { ctrl_c }

      publish
      @logger.log "Originator finished successfully"
    rescue StandardError
      puts "Unhandled exception in originator:"
      puts $!.message
      puts $!.backtrace.join("\n")
      puts "----------------------------------"
      puts "Now attempting to cancel the job."
      @logger.log_error "Unhandled Exception!" if @logger
      cancel_job
    end
  end

  def cancel_job
    ShutdownManager.new(protocol: @protocol,
                        job_state: @job_state).cancel_job
  end

  def ctrl_c
    puts "\nCtrl-C received! Just wait a moment while I clean up..."
    cancel_job
  end

  def publish
    @logger = OriginatorLogger.new configuration[:originator_log_file]

    if files.empty?
      $stderr.puts "There are no files to test! Quitting."
      exit 2
    end

    push_source_code

    @protocol = OriginatorProtocol.new @logger

    EventMachine.run do
      @logger.log "Connecting..."
      @protocol.connect connection_information, :on_closed => method(:on_disconnect)

      @logger.log "Publishing files..."
      @protocol.publish_files files
      create_job_state_and_observers

      @logger.log "Publishing Job..."
      @protocol.publish_job job_definition
      @logger.log "Job Published"

      @protocol.receive_payloads do |payload|
        handle_reply(payload)
      end
    end
  end

  def push_source_code
    syncer = SourceTreeSyncer.new(source_tree_path)
    syncer.exclude = configuration[:sync_exclude]
    syncer.push
    if syncer.success?
      @logger.log "Command '#{syncer.sys_command}' completed successfully."
    else
      $stderr.puts "Command '#{syncer.sys_command}' failed!"
      $stderr.puts "Stdout:\n#{syncer.output}"
      $stderr.puts "Stderr:\n#{syncer.errors}"
      exit 1
    end
  end

  def cleanup_if_job_complete
    if @job_state.is_job_complete?
      @logger.log "Job is done"
      @protocol.disconnect
    end
  end

  def handle_reply(payload)
    payload = Yajl::Parser.new(:symbolize_keys => true).parse(payload)

    # at some point this will probably need to be fancy polymorphic type based responses, or at least a nice switch statement
    if payload[:action] == "finish"
      @job_state.file_finished payload
    elsif payload[:action] == "start"
      @job_state.file_started payload
    elsif payload[:type] == "crash"
      @job_state.gorgon_crash_message payload
    elsif payload[:type] == "exception"
      # TODO
      ap payload
    else
      ap payload
    end

    @logger.log_message payload
    # Uncomment this to see each message received by originator
    # ap payload

    cleanup_if_job_complete
  end

  def create_job_state_and_observers
    @job_state = JobState.new files.count
    @progress_bar_view = ProgressBarView.new @job_state
    @progress_bar_view.show
    failures_printer = FailuresPrinter.new @job_state
  end

  def on_disconnect
    EventMachine.stop
  end

  def connection_information
    configuration[:connection]
  end

  def files
    @files ||= configuration[:files].reduce([]) do |memo, obj|
      memo.concat(Dir[obj])
    end.uniq
  end

  def job_definition
    job_config = configuration[:job]
    if !job_config.has_key?(:source_tree_path)
      job_config[:source_tree_path] = source_tree_path
    end
    JobDefinition.new(configuration[:job])
  end

  private

  def source_tree_path
    "rsync://#{file_server_host}:43434/src"
  end

  def file_server_host
    file_server = configuration[:file_server]
    raise 'Please, provide file_server configuration.' if file_server.nil?
    configuration[:file_server][:host]
  end

  def configuration
    @configuration ||= load_configuration_from_file("gorgon.json")
  end
end
