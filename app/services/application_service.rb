# Base class for every service: one business action per class.
# Copied from control-tower/templates/rails. The rules are in control-tower/RAILS.md.
#
#   class Articles::PublishService < ApplicationService
#     attr_accessor :article, :user          # inputs
#     attr_reader :notification              # outputs
#
#     validates :article, :user, presence: true
#     validate :user_owns_article            # preconditions read like a spec
#
#     private
#
#     def execute
#       transaction do
#         article.update(published_at: Time.current)
#         absorb_errors(article)
#         after_commit { ArticleMailer.published(article).deliver_later }
#       end
#     end
#   end
#
# Controllers branch on #call. Jobs use #call!, so a failure raises instead of vanishing.
#
#   service = Articles::PublishService.new(article:, user: Current.user)
#   if service.call
#     redirect_to service.article
#   else
#     render :edit, status: :unprocessable_entity   # service.errors says why
#   end
class ApplicationService
  include ActiveModel::Model

  class Failed < StandardError
    attr_reader :service

    def initialize(service)
      @service = service
      super("#{service.class.name} failed: #{service.errors.full_messages.to_sentence}")
    end
  end

  # Runs the validations, then #execute. True when both pass, false with #errors set otherwise.
  def call
    return false unless valid?

    execute
    errors.none?
  end

  def call!
    call || raise(Failed.new(self))
  end

  private

  def execute
    raise NotImplementedError, "#{self.class.name} must implement #execute"
  end

  # Rolls the transaction back if the block left errors on the service.
  def transaction
    ActiveRecord::Base.transaction do
      yield
      raise ActiveRecord::Rollback if errors.any?
    end
  end

  # Copies a record's validation errors onto the service. True when the record had none.
  def absorb_errors(record)
    errors.merge!(record.errors)
    record.errors.none?
  end

  # Runs the block once the surrounding transaction commits, or right away outside one.
  # Never runs after a rollback. Needs Rails 7.2 or newer.
  def after_commit(&block)
    ActiveRecord.after_all_transactions_commit(&block)
  end
end
