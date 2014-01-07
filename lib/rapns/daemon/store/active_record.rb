require 'active_record'

require 'rapns/daemon/store/active_record/reconnectable'

module Rapns
  module Daemon
    module Store
      class ActiveRecord
        include Reconnectable

        def deliverable_notifications(apps)
          with_database_reconnect_and_retry do
            batch_size = Rapns.config.batch_size
            relation = Rapns::Notification.ready_for_delivery.for_apps(apps)
            relation = relation.limit(batch_size) unless Rapns.config.push
            relation.to_a
          end
        end

        def mark_retryable(notification, deliver_after, opts = {:persist => true})
          notification.retries += 1
          notification.deliver_after = deliver_after

          if opts[:persist]
            with_database_reconnect_and_retry do
              notification.save!(:validate => false)
            end
          end
        end

        def mark_batch_retryable(notifications, deliver_after)
          ids = []
          notifications.each do |n|
            mark_retryable(n, deliver_after, :persist => false)
            ids << n.id
          end
          with_database_reconnect_and_retry do
            Rapns::Notification.where(:id => ids).update_all(['retries = retries + 1, deliver_after = ?', deliver_after])
          end
        end

        def mark_delivered(notification, time, opts = {:persist => true})
          notification.delivered = true
          notification.delivered_at = time

          if opts[:persist]
            with_database_reconnect_and_retry do
              notification.save!(:validate => false)
            end
          end
        end

        def mark_batch_delivered(notifications)
          now = Time.now
          ids = []
          notifications.each do |n|
            mark_delivered(n, now, :persist => false)
            ids << n.id
          end
          with_database_reconnect_and_retry do
            Rapns::Notification.where(:id => ids).update_all(['delivered = ?, delivered_at = ?', true, now])
          end
        end

        def mark_failed(notification, code, description, time, opts = {:persist => true})
          notification.delivered = false
          notification.delivered_at = nil
          notification.failed = true
          notification.failed_at = time
          notification.error_code = code
          notification.error_description = description

          if opts[:persist]
            with_database_reconnect_and_retry do
              notification.save!(:validate => false)
            end
          end
        end

        def mark_batch_failed(notifications, code, description)
          now = Time.now
          ids = []
          notifications.each do |n|
            mark_failed(n, code, description, now, :persist => false)
            ids << n.id
          end
          with_database_reconnect_and_retry do
            Rapns::Notification.where(:id => ids).update_all(['delivered = ?, delivered_at = NULL, failed = ?, failed_at = ?, error_code = ?, error_description = ?', false, true, now, code, description])
          end
        end

        def create_apns_feedback(failed_at, device_token, app)
          with_database_reconnect_and_retry do
            Rapns::Apns::Feedback.create!(:failed_at => failed_at,
              :device_token => device_token, :app => app)
          end
        end

        def create_gcm_notification(attrs, data, registration_ids, deliver_after, app)
          with_database_reconnect_and_retry do
            notification = Rapns::Gcm::Notification.new
            notification.assign_attributes(attrs)
            notification.data = data
            notification.registration_ids = registration_ids
            notification.deliver_after = deliver_after
            notification.app = app
            notification.save!
            notification
          end
        end

        def create_wpns_notification(attrs,data,uri, app)
          with_database_reconnect_and_retry do
            notification = Rapns::Wpns::Notification.new
            notification.assign_attributes(attrs)
            notification.data = data
            notification.uri = uri
            notification.app = app
            notification.save!
            notification
          end
        end

        def after_daemonize
          reconnect_database
        end
      end
    end
  end
end
