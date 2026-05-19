# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecordClickJob, type: :job do
  let(:short_link) { create(:short_link) }
  let(:occurred_at) { Time.zone.local(2026, 5, 19, 12, 30, 0) }

  around do |example|
    original = ENV["CLICK_IP_SALT"]
    ENV["CLICK_IP_SALT"] = "test-salt"
    example.run
  ensure
    ENV["CLICK_IP_SALT"] = original
  end

  before do
    allow(GeolocationService).to receive(:lookup).with("8.8.8.8")
      .and_return(GeolocationService::Result.new(country: "US", city: "Mountain View"))
  end

  describe "#perform" do
    it "creates a Click row with hashed IP, country, city, and the original occurred_at" do
      expect {
        described_class.perform_now(short_link.id, "8.8.8.8", occurred_at.iso8601)
      }.to change(Click, :count).by(1)

      click = Click.last
      expect(click.short_link).to eq(short_link)
      expect(click.country).to eq("US")
      expect(click.city).to eq("Mountain View")
      expect(click.ip_hash).to eq(Digest::SHA256.hexdigest("8.8.8.8test-salt"))
      expect(click.occurred_at).to be_within(1.second).of(occurred_at)
    end

    it "still writes a Click with country='ZZ' when geolocation falls through" do
      allow(GeolocationService).to receive(:lookup)
        .and_return(GeolocationService::Result.new(country: "ZZ", city: nil))

      described_class.perform_now(short_link.id, "8.8.8.8", occurred_at.iso8601)

      click = Click.last
      expect(click.country).to eq("ZZ")
      expect(click.city).to be_nil
    end

    it "is a no-op when the short_link no longer exists" do
      expect {
        described_class.perform_now(999_999, "8.8.8.8", occurred_at.iso8601)
      }.not_to change(Click, :count)
    end

    it "preserves the controller-captured occurred_at on retries, not the job run time" do
      # The job re-uses the timestamp the controller captured, so a delayed
      # worker run doesn't pollute analytics with re-execution times.
      old_time = 2.hours.ago

      described_class.perform_now(short_link.id, "8.8.8.8", old_time.iso8601)

      expect(Click.last.occurred_at).to be_within(1.second).of(old_time)
    end
  end

  describe "error handling" do
    it "re-enqueues itself when GeolocationService raises a transient error" do
      allow(GeolocationService).to receive(:lookup).and_raise(Net::OpenTimeout)

      expect {
        described_class.perform_now(short_link.id, "8.8.8.8", occurred_at.iso8601)
      }.to have_enqueued_job(described_class).with(short_link.id, "8.8.8.8", occurred_at.iso8601)
    end
  end
end
