# frozen_string_literal: true

RSpec.describe SasLexer do
  it "exposes a VERSION" do
    expect(SasLexer::VERSION).to be_a(String)
  end

  it "defines an Error class derived from StandardError" do
    expect(SasLexer::Error.ancestors).to include(StandardError)
  end
end
