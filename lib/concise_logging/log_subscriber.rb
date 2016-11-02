module ConciseLogging
  class LogSubscriber < ActiveSupport::LogSubscriber
    INTERNAL_PARAMS = %w(controller action format _method only_path)

    def redirect_to(event)
      Thread.current[:logged_location] = event.payload[:location]
    end

    def process_action(event)
      payload = event.payload
      param_method = payload[:params]["_method"]
      method = param_method ? param_method.upcase : payload[:method]
      status, exception_details = compute_status(payload)
      path = payload[:path].to_s.gsub(/\?.*/, "")
      params = payload[:params].except(*INTERNAL_PARAMS)

      ip = Thread.current[:logged_ip]
      location = Thread.current[:logged_location]
      Thread.current[:logged_location] = nil

      app = payload[:view_runtime].to_i
      db = payload[:db_runtime].to_i

      message = format(
        "%{severity} %{time} [%{session_id}] %{method} %{status} %{ip} %{path}",
        severity: format_severity(status),
        ip: format("%-15s", ip),
        method: format_method(format("%-6s", method)),
        status: format_status(status),
        path: path,
        time: Time.now,
        session_id: Thread.current[:session_id]
      )
      message << " redirect_to=#{location}" if location.present?
      message << " parameters=#{params}" if params.present?
      message << " #{color(exception_details, RED)}" if exception_details.present?
      message << " (current_user.id: #{RequestStore.store[:user_id]})" unless RequestStore.store[:user_id].blank?

      logger.warn message 
    end

    def compute_status(payload)
      details = nil
      status = payload[:status]
      if status.nil? && payload[:exception].present?
        exception_class_name = payload[:exception].first
        status = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception_class_name)

        if payload[:exception].respond_to?(:uniq)
          details = payload[:exception].uniq.join(" ")
        end
      end
      [status, details]
    end

    def format_method(method)
      if method.strip == "GET"
        method
      else
        color(method, CYAN)
      end
    end

    def format_status(status)
      status = status.to_i
      if status >= 500
        color(status, MAGENTA)
      elsif status >= 400
        color(status, RED)
      elsif status >= 300
        color(status, YELLOW)
      else
        color(status, GREEN)
      end
    end

    def format_severity(status)
      status = status.to_i
      if status >= 500
        color('Logger:critical', MAGENTA)
      elsif status >= 400
        'Logger:error'
      elsif status >= 300
        'Logger:warn'
      else
        'Logger:info'
      end
    end
  end
end
