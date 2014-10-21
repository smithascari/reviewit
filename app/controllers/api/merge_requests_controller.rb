module Api
  class MergeRequestsController < ApiController

    def index
      render json: project.merge_requests.pending
    end

    def show
      patch = merge_request.patch
      raise 'No patches were found for this merge request.' unless patch.is_a? Patch

      render json: {
        id: @mr.id,
        target_branch:  @mr.target_branch,
        status:         @mr.status,
        author:         @mr.author.name,
        author_email:   @mr.author.email,
        commit_message: @mr.commit_message,
        diff:           patch.diff
      }
    end

    def destroy
      raise 'You can not abandon a merge request in the integration process, wait a bit.' if merge_request.integrating?
      raise 'Too late, this merge request was already accepted.' if merge_request.accepted?
      raise 'This merge request was already abandoned.' if merge_request.abandoned?
      merge_request.abandon! current_user
      render json: {}
    end

    def show_git_patch
      render json: { patch: merge_request.git_format_patch }
    end

    def create
      MergeRequest.transaction do
        mr = MergeRequest.new
        mr.project = project
        mr.author = current_user
        mr.subject = params[:subject]
        mr.target_branch = params[:target_branch]

        mr.save!

        patch = Patch.new
        patch.merge_request = mr
        patch.commit_message = params[:commit_message]
        patch.diff = params[:diff]
        patch.description = ''
        patch.save!
        render(json: { :mr_id => mr.id })
      end
    end

    def update
      mr = merge_request

      raise 'Seems you are re-submitting the same patch.' if is_it_a_mistake?
      raise 'You need to be the MR author to update it.' if mr.author != current_user
      raise "You can not update a #{mr.status} merge request." unless mr.can_update?

      MergeRequest.transaction do
        mr.subject = params[:subject]
        mr.status = :open
        mr.save!

        patch = Patch.new
        patch.merge_request = mr
        patch.commit_message = params[:commit_message]
        patch.diff = params[:diff]
        patch.description = (params[:description] or '').lines.first.to_s
        patch.save!

        render json: {}
      end
    end

    private

    def is_it_a_mistake?
      last_patch = merge_request.patch
      last_patch.diff == params[:diff] and last_patch.commit_message == params[:commit_message]
    end
  end
end
