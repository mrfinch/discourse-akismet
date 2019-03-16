require 'rails_helper'

describe DiscourseAkismet::CheckSpamUser do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true

    user.user_profile.update!(bio_raw: bio)
  end

  let(:user) { Fabricate(:newuser) }

  let(:bio) { 'random profile' }

  let(:akismet_url_regex) { /rest.akismet.com/ }

  it 'checks job is enqueued on user create' do
    user
    jobs = Jobs::CheckAkismetUser.jobs.select do |job|
      job['class'] == 'Jobs::CheckAkismetUser' && job['args'] &&
      job['args'].select { |arg| arg['user_id'] == user.id }.count == 1
    end

    expect(jobs.count).to eq(1)
  end

  describe '#check_for_spam' do

    it 'moves spam user to NEEDS_REVIEW' do
      stub_request(:post, akismet_url_regex).
        to_return(status: 200, body: "true", headers: {})

      described_class.new(user, user.user_profile.bio_raw).check_for_spam

      expect(UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY, user_id: user.id).first.value).to eq(DiscourseAkismet::NEEDS_REVIEW)
    end

    it 'moves valid user to CHECKED' do
      stub_request(:post, akismet_url_regex).
        to_return(status: 200, body: "false", headers: {})

      described_class.new(user, user.user_profile.bio_raw).check_for_spam

      expect(UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY, user_id: user.id).first.value).to eq(DiscourseAkismet::CHECKED)
    end

  end

  describe '#should_check_for_spam' do

    it 'does not check when user is blank' do
      expect(described_class.new(nil, user.user_profile.bio_raw).should_check_for_spam?).to eq(false)
    end

    it 'checks when user is level 0' do
      expect(described_class.new(user, user.user_profile.bio_raw).should_check_for_spam?).to eq(true)
    end

    it 'does not check when site setting is disabled' do
      SiteSetting.akismet_enabled = false

      expect(described_class.new(user, user.user_profile.bio_raw).should_check_for_spam?).to eq(false)

      SiteSetting.akismet_enabled = true
      SiteSetting.akismet_api_key = nil
      expect(described_class.new(user, user.user_profile.bio_raw).should_check_for_spam?).to eq(false)
    end

    it 'does not check when user trust level is not 0' do
      user.trust_level = 1
      user.save

      expect(described_class.new(user, user.user_profile.bio_raw).should_check_for_spam?).to eq(false)
    end

    it 'returns false when user bio is empty' do
      user_profile = user.user_profile
      user_profile.bio_raw = nil
      user_profile.save

      expect(described_class.new(user, user.user_profile.bio_raw).should_check_for_spam?).to eq(false)
    end

  end

  describe '.to_check' do

    it 'returns tl0 user who are not checked for spam' do
      user

      result = described_class.to_check
      expect(result.where(id: user.id).count).to eq(1)

      user.upsert_custom_fields(DiscourseAkismet::AKISMET_STATE_KEY => DiscourseAkismet::NEEDS_REVIEW)
      result = described_class.to_check
      expect(result.where(id: user.id).count).to eq(0)
    end

  end

end