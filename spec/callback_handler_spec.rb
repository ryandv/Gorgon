require 'gorgon/callback_handler'

describe CallbackHandler do

  let(:config) {
    {
      :before_start => "some/file.rb",
      :after_complete => "some/other/file.rb"
    }
  }

  it "calls before hook" do
    handler = CallbackHandler.new(config)

    handler.should_receive(:load).with("some/file.rb")

    handler.before_start
  end

  it "does not attempt to load the before start script when before_start is not defined" do
    handler = CallbackHandler.new({})

    handler.should_not_receive(:load)

    handler.before_start
  end

  it "calls after hook" do
    handler = CallbackHandler.new(config)

    handler.should_receive(:load).with("some/other/file.rb")

    handler.after_complete
  end

  it "does not attempt to load the after complete script when before_start is not defined" do
    handler = CallbackHandler.new({})

    handler.should_not_receive(:load)

    handler.after_complete
  end
end