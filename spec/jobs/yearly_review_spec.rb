require 'rails_helper'

describe Jobs::YearlyReview do
  SiteSetting.yearly_review_enabled = true
  let(:top_review_user) { Fabricate(:user, username: 'top_review_user') }
  let(:reviewed_user) { Fabricate(:user, username: 'reviewed_user') }
  describe 'publishing the topic' do
    context 'January 1, 2019' do
      before do
        freeze_time DateTime.parse('2019-01-01')
        Fabricate(:topic, created_at: 1.month.ago)
      end

      it 'publishes a review topic' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        expect(topic.title).to eq(I18n.t('yearly_review.topic_title', year: 2018))
      end
    end

    context 'January 5, 2019' do
      before do
        freeze_time DateTime.parse('2019-01-05')
        Fabricate(:topic, created_at: 1.month.ago)
      end

      it 'publishes a review topic' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        expect(topic.title).to eq(I18n.t('yearly_review.topic_title', year: 2018))
      end
    end

    context 'February 1, 2019' do
      before do
        freeze_time DateTime.parse('2019-02-01')
        Fabricate(:topic, created_at: 2.months.ago, title: 'A topic from 2018')
      end

      it "doesn't publish a review topic" do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        expect(topic.title).to eq('A topic from 2018')
      end
    end

    context 'After the review has been published' do
      before do
        freeze_time DateTime.parse('2019-01-05')
        Fabricate(:topic, created_at: 1.month.ago)
        Jobs::YearlyReview.new.execute({})
        Fabricate(:topic, title: 'The last topic published')
        Jobs::YearlyReview.new.execute({})
      end

      it "doesn't publish the review topic twice" do
        topic = Topic.last
        expect(topic.title).to eq('The last topic published')
      end
    end
  end

  describe 'review categories' do
    before do
      freeze_time DateTime.parse('2019-01-01')
      review_category = Fabricate(:category, topics_year: 100)
      non_review_category = Fabricate(:category, topics_year: 100)
      group = Fabricate(:group)
      non_review_category.set_permissions(group => :full)
      non_review_category.save
      private_topic = Fabricate(:topic, category_id: non_review_category.id, title: 'A topic in a private category' , created_at: 1.month.ago)
      public_topic = Fabricate(:topic, category_id: review_category.id, posts_count: 100, title: 'A topic in a public category', created_at: 1.month.ago)
      20.times do
        Fabricate(:post, topic: private_topic, created_at: 1.month.ago)
      end
      20.times do
        Fabricate(:post, topic: public_topic, created_at: 1.month.ago)
      end
    end

    it 'only displays data from public categories' do
      Jobs::YearlyReview.new.execute({})
      topic = Topic.last
      raw = Post.where(topic_id: topic.id).first.raw
      puts "#{raw}"
      expect(raw).not_to have_tag('a', text: /A topic in a private category/)
      expect(raw).to have_tag('a', text: /A topic in a public category/)
    end
  end

  describe 'user stats' do
    before do
      freeze_time DateTime.parse('2019-01-01')
    end

    context 'most topics' do
      before do
        5.times { Fabricate(:topic, user: top_review_user, created_at: 1.month.ago) }
        Fabricate(:topic, user: reviewed_user, created_at: 1.month.ago)
      end

      it 'ranks topics created by users correctly' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        raw = Post.where(topic_id: topic.id).first.raw
        expect(raw).to have_tag('table.topics-created tr.user-row-0') { with_tag('td', text: /5/) }
        expect(raw).to have_tag('table.topics-created tr.user-row-1') { with_tag('td', text: /1/) }
      end
    end

    context 'most replies' do
      before do
        SiteSetting.max_consecutive_replies = 5
        topic_user = Fabricate(:user)
        reviewed_topic = Fabricate(:topic, user: topic_user, created_at: 1.year.ago)
        Fabricate(:post, topic: reviewed_topic, user: topic_user)
        5.times { Fabricate(:post, topic: reviewed_topic, user: top_review_user, created_at: 1.month.ago) }
        Fabricate(:post, topic: reviewed_topic, user: reviewed_user, created_at: 1.month.ago)
      end

      it 'ranks replies created by users correctly' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        raw = Post.where(topic_id: topic.id).first.raw
        expect(raw).to have_tag('table.replies-created tr.user-row-0') { with_tag('td', text: /5/) }
        expect(raw).to have_tag('table.replies-created tr.user-row-1') { with_tag('td', text: /1/) }
      end
    end

    context 'likes given and received' do
      SiteSetting.max_consecutive_replies = 20
      let(:reviewed_topic) { Fabricate(:topic, created_at: 1.year.ago) }
      before do
        11.times do
          post = Fabricate(:post, topic: reviewed_topic, user: reviewed_user, created_at: 1.month.ago)
          UserAction.create!(action_type: PostActionType.types[:like],
                             user_id: reviewed_user.id,
                             acting_user_id: top_review_user.id,
                             target_post_id: post.id,
                             target_topic_id: reviewed_topic.id,
                             created_at: 1.month.ago)
        end
        10.times do
          post = Fabricate(:post, topic: reviewed_topic, user: top_review_user, created_at: 1.month.ago)
          UserAction.create!(action_type: PostActionType.types[:like],
                             user_id: top_review_user.id,
                             acting_user_id: reviewed_user.id,
                             target_post_id: post.id,
                             target_topic_id: reviewed_topic.id,
                             created_at: 1.month.ago)
        end
      end

      it 'should rank likes given and received correctly' do
        Jobs::YearlyReview.new.execute({})
        topic = Topic.last
        raw = Post.where(topic_id: topic.id).first.raw
        expect(raw).to have_tag('table.likes-given tr.user-row-0') { with_tag('td', text: /11/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-0') { with_tag('td', text: /@top_review_user/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-1') { with_tag('td', text: /10/) }
        expect(raw).to have_tag('table.likes-given tr.user-row-1') { with_tag('td', text: /@reviewed_user/) }

        expect(raw).to have_tag('table.likes-received tr.user-row-0') { with_tag('td', text: /11/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-0') { with_tag('td', text: /@reviewed_user/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-1') { with_tag('td', text: /10/) }
        expect(raw).to have_tag('table.likes-received tr.user-row-1') { with_tag('td', text: /@top_review_user/) }
      end
    end
  end

  describe 'featured badge' do
    let(:admin) { Fabricate(:user, admin: true) }
    let(:badge) { Fabricate(:badge) }
    before do
      SiteSetting.yearly_review_featured_badge = badge.name
      freeze_time DateTime.parse('2019-01-01')
      101.times do
        user = Fabricate(:user)
        UserBadge.create!(badge_id: badge.id,
                          user_id: user.id,
                          granted_at: 1.month.ago,
                          granted_by_id: admin.id)
      end
    end

    it "it should only display the first 100 users" do
      Jobs::YearlyReview.new.execute({})
      topic = Topic.last
      raw = Post.where(topic_id: topic.id).first.raw
      expect(raw).to have_tag('a', text: /And 1 more/)
    end
  end
end
