module Rpush
  module Daemon
    module Store
      class Mongoid
        DEFAULT_MARK_OPTIONS = { persist: true }

        def app(app_id)
          Rpush::Client::Mongoid::App.find(app_id)
        end

        def all_apps
          Rpush::Client::Mongoid::App.all
        end

        def deliverable_notifications(limit)
          relation = ready_for_delivery.limit(limit)
          claim_notifications(relation)
        end

        def mark_delivered(notification, time, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.delivered = true
          notification.delivered_at = time
          notification.save!(validate: false) if opts[:persist]
        end

        def mark_batch_delivered(notifications)
          now = Time.now
          notifications.each { |n| mark_delivered(n, now) }
        end

        def mark_failed(notification, code, description, time, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.delivered = false
          notification.delivered_at = nil
          notification.failed = true
          notification.failed_at = time
          notification.error_code = code
          notification.error_description = description
          notification.save!(validate: false) if opts[:persist]
        end

        def mark_batch_failed(notifications, code, description)
          now = Time.now
          notifications.each { |n| mark_failed(n, code, description, now) }
        end

        def mark_ids_failed(ids, code, description, time)
          ids.each { |id| mark_failed(Rpush::Client::Mongoid::Notification.find(id), code, description, time) }
        end

        def mark_retryable(notification, deliver_after, opts = {})
          opts = DEFAULT_MARK_OPTIONS.dup.merge(opts)
          notification.delivered = false
          notification.delivered_at = nil
          notification.failed = false
          notification.failed_at = nil
          notification.retries += 1
          notification.deliver_after = deliver_after

          return unless opts[:persist]

          notification.save!(validate: false)
        end

        def mark_batch_retryable(notifications, deliver_after)
          notifications.each { |n| mark_retryable(n, deliver_after) }
        end

        def mark_ids_retryable(ids, deliver_after)
          ids.each { |id| mark_retryable(Rpush::Client::Mongoid::Notification.find(id), deliver_after) }
        end

        def create_apns_feedback(failed_at, device_token, app)
          Rpush::Client::Mongoid::Apns::Feedback.create!(failed_at: failed_at, device_token: device_token, app: app)
        end

        def create_gcm_notification(attrs, data, registration_ids, deliver_after, app) # rubocop:disable ParameterLists
          notification = Rpush::Client::Mongoid::Gcm::Notification.new
          create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app)
        end

        def create_adm_notification(attrs, data, registration_ids, deliver_after, app) # rubocop:disable ParameterLists
          notification = Rpush::Client::Mongoid::Adm::Notification.new
          create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app)
        end

        def update_app(app)
          app.save!
        end

        def update_notification(notification)
          notification.save!
        end

        def release_connection
        end

        def reopen_log
        end

        def pending_delivery_count
          ready_for_delivery.count
        end

        def translate_integer_notification_id(id)
          Rpush::Client::Mongoid::Notification.find_by(integer_id: id).id
        end

        private

        def ready_for_delivery
          Rpush::Client::Mongoid::Notification.where(processing: false, delivered: false, failed: false).or({ deliver_after: nil }, :deliver_after.lt => Time.now)
        end

        def mark_processing(notifications)
          Rpush::Client::Mongoid::Notification.where(id: notifications.map(&:id)).update_all(processing: true)
        end

        def claim_notifications(relation)
          ids = relation.map(:id)
          relation.where('$isolated' => 1).in(id: ids).update_all(processing: true, processing_pid: Process.pid)
          Rpush::Client::Mongoid::Notification.where(processing: true, processing_pid: Process.pid).in(id: ids).asc('created_at')
        end

        def create_gcm_like_notification(notification, attrs, data, registration_ids, deliver_after, app) # rubocop:disable ParameterLists
          notification.assign_attributes(attrs)
          notification.data = data
          notification.registration_ids = registration_ids
          notification.deliver_after = deliver_after
          notification.app = app
          notification.save!
          notification
        end
      end
    end
  end
end

Rpush::Daemon::Store::Interface.check(Rpush::Daemon::Store::Mongoid)
