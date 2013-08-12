class AddStatisticsToPublicBody < ActiveRecord::Migration
  def change
    add_column :public_bodies, :info_requests_successful_count, :integer
    add_column :public_bodies, :info_requests_not_held_count, :integer
    add_column :public_bodies, :info_requests_overdue, :integer
  end
end
