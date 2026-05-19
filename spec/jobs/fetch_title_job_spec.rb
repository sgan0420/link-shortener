# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchTitleJob, type: :job do
  let(:short_link) { create(:short_link, target_url: "https://example.com") }

  before do
    # Block real Turbo broadcasts in tests so we don't try to render a
    # partial that doesn't exist yet (Phase 7). Specs that care about
    # the broadcast use `expect(...)` to override.
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "updates short_link with the fetched title on success" do
      allow(TitleFetcher).to receive(:call).with(url: short_link.target_url)
        .and_return(TitleFetcher::Result.new(ok: true, title: "Example Page"))

      described_class.perform_now(short_link.id)

      short_link.reload
      expect(short_link.title).to eq("Example Page")
      expect(short_link).to be_fetched
    end

    it "marks failed when TitleFetcher returns ok=false" do
      allow(TitleFetcher).to receive(:call)
        .and_return(TitleFetcher::Result.new(ok: false, reason: "boom"))

      described_class.perform_now(short_link.id)

      expect(short_link.reload).to be_failed
    end

    it "broadcasts a Turbo Stream replace on success" do
      allow(TitleFetcher).to receive(:call)
        .and_return(TitleFetcher::Result.new(ok: true, title: "Example Page"))

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        short_link,
        target: ActionView::RecordIdentifier.dom_id(short_link, :title),
        partial: "short_links/title",
        locals: hash_including(short_link: instance_of(ShortLink))
      )

      described_class.perform_now(short_link.id)
    end

    it "is a no-op when the short_link no longer exists" do
      expect(TitleFetcher).not_to receive(:call)
      expect {
        described_class.perform_now(999_999)
      }.not_to raise_error
    end
  end

  describe "error handling" do
    it "discards on PrivateAddressError and marks failed" do
      allow(TitleFetcher).to receive(:call).and_raise(TitleFetcher::PrivateAddressError)

      expect {
        described_class.perform_now(short_link.id)
      }.not_to raise_error

      expect(short_link.reload).to be_failed
    end

    it "re-enqueues itself when TitleFetcher raises a transient error (retry_on routing)" do
      allow(TitleFetcher).to receive(:call).and_raise(Net::OpenTimeout)

      expect {
        described_class.perform_now(short_link.id)
      }.to have_enqueued_job(described_class).with(short_link.id)
    end
  end

  describe ".mark_failed" do
    it "sets title_status to failed and broadcasts the swap" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        short_link,
        hash_including(
          target: ActionView::RecordIdentifier.dom_id(short_link, :title),
          partial: "short_links/title"
        )
      )

      described_class.mark_failed(short_link.id)

      expect(short_link.reload).to be_failed
    end

    it "is a no-op for a missing short_link" do
      expect {
        described_class.mark_failed(999_999)
      }.not_to raise_error
    end
  end
end
