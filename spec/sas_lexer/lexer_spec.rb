# frozen_string_literal: true

RSpec.describe SasLexer::Lexer do
  describe "#initialize" do
    it "creates a new lexer instance" do
      lexer = described_class.new
      expect(lexer).to be_a(described_class)
      lexer.free
    end
  end

  describe "LIBRARY_PATH" do
    it "resolves to a real file under lib/native/" do
      expect(File.exist?(described_class::LIBRARY_PATH)).to be true
    end
  end

  describe "#tokenize" do
    let(:lexer) { described_class.new }

    after { lexer.free }

    context "with valid SAS code" do
      it "returns an array of tokens" do
        tokens = lexer.tokenize("data test; set input; run;")
        expect(tokens).to be_an(Array)
        expect(tokens).not_to be_empty
      end

      it "yields token hashes with text, type, channel, and position" do
        tokens = lexer.tokenize("data test;")
        expect(tokens.first).to include(
          :index, :text, :type, :channel,
          :start, :end, :start_line, :end_line,
          :start_column, :end_column
        )
      end

      it "tags the leading 'data' token as a SAS keyword" do
        tokens = lexer.tokenize("data test; run;").reject { |t| t[:channel] == SasLexer::Lexer::TokenChannel::HIDDEN }
        first = tokens.first
        expect(first[:text].downcase).to eq("data")
        expect(first[:type]).to eq(SasLexer::Lexer::TokenType::KW_DATA)
      end
    end

    context "with nil input" do
      it "raises an error" do
        expect { lexer.tokenize(nil) }.to raise_error(SasLexer::Error, /Null pointer provided/)
      end
    end

    context "when the lexer has been freed" do
      it "raises an error on tokenize" do
        lexer.free
        expect { lexer.tokenize("data test;") }.to raise_error(SasLexer::Error, "Lexer has been freed")
      end
    end
  end

  describe "#free" do
    it "can be called multiple times safely" do
      lexer = described_class.new
      lexer.free
      expect { lexer.free }.not_to raise_error
    end
  end
end
