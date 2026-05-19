# frozen_string_literal: true

require "rails_helper"

RSpec.describe TitleFetcher do
  before do
    # By default, resolve to a known-public IP so the SSRF guard passes.
    # Specs that exercise the guard override this with allow().with(host).
    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ])
  end

  describe ".call" do
    it "returns the parsed <title>" do
      stub_request(:get, "https://example.com/page")
        .to_return(status: 200,
                   body: "<html><head><title>  Hello  World  </title></head></html>",
                   headers: { "Content-Type" => "text/html" })

      result = described_class.call(url: "https://example.com/page")

      expect(result.ok?).to be(true)
      expect(result.title).to eq("Hello World")
    end

    it "returns ok=false on missing <title>" do
      stub_request(:get, "https://example.com/notitle")
        .to_return(status: 200, body: "<html><head></head></html>")

      result = described_class.call(url: "https://example.com/notitle")

      expect(result.ok?).to be(false)
    end

    it "truncates very long titles to 512 chars" do
      long = "a" * 1000
      stub_request(:get, "https://example.com/long")
        .to_return(status: 200, body: "<html><head><title>#{long}</title></head></html>")

      result = described_class.call(url: "https://example.com/long")

      expect(result.title.length).to eq(512)
    end

    it "raises PrivateAddressError when hostname resolves to a private IP" do
      allow(Resolv).to receive(:getaddresses).with("internal.local").and_return([ "10.0.0.1" ])

      expect {
        described_class.call(url: "https://internal.local/x")
      }.to raise_error(TitleFetcher::PrivateAddressError)
    end

    it "raises PrivateAddressError for loopback" do
      allow(Resolv).to receive(:getaddresses).with("localhost").and_return([ "127.0.0.1" ])

      expect {
        described_class.call(url: "http://localhost/x")
      }.to raise_error(TitleFetcher::PrivateAddressError)
    end

    it "returns ok=false on HTTP timeout" do
      stub_request(:get, "https://example.com/slow").to_timeout

      result = described_class.call(url: "https://example.com/slow")

      expect(result.ok?).to be(false)
      expect(result.reason).to match(/timeout|timed out|execution expired/i)
    end

    it "returns ok=false on 5xx response" do
      stub_request(:get, "https://example.com/boom").to_return(status: 503, body: "")

      result = described_class.call(url: "https://example.com/boom")

      expect(result.ok?).to be(false)
    end

    it "aborts reading once body exceeds MAX_BODY_BYTES, ignoring content past the cap" do
      # If we keep reading past the cap, the late <title> would be parsed.
      # With streaming + early break, we stop before reaching it and report
      # "no title element" as a soft failure.
      stub_const("#{described_class.name}::MAX_BODY_BYTES", 32)
      body = ("A" * 200) + "<title>Late</title>"
      stub_request(:get, "https://example.com/big")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html" })

      result = described_class.call(url: "https://example.com/big")

      expect(result.ok?).to be(false)
      expect(result.reason).to match(/no title element/i)
    end
  end
end
