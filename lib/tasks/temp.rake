namespace :temp do

    desc 'Populate the request_classifications table from info_request_events'
    task :populate_request_classifications => :environment do
        InfoRequestEvent.find_each(:conditions => ["event_type = 'status_update'"]) do |classification|
            RequestClassification.create!(:created_at => classification.created_at,
                                          :user_id => classification.params[:user_id],
                                          :info_request_event_id => classification.id)
        end
    end

    desc "Remove plaintext passwords from post_redirect params"
    task :remove_post_redirect_passwords => :environment do
        PostRedirect.find_each(:conditions => ['post_params_yaml is not null']) do |post_redirect|
              if post_redirect.post_params && post_redirect.post_params[:signchangeemail] && post_redirect.post_params[:signchangeemail][:password]
                params = post_redirect.post_params
                params[:signchangeemail].delete(:password)
                post_redirect.post_params = params
                post_redirect.save!
              end
        end
    end

    desc 'Remove file caches for requests that are not publicly visible or have been destroyed'
    task :remove_obsolete_info_request_caches => :environment do
        dryrun = ENV['DRYRUN'] == '0' ? false : true
        verbose = ENV['VERBOSE'] == '0' ? false : true
        if dryrun
            puts "Running in dryrun mode"
        end
        request_cache_path = File.join(Rails.root, 'cache', 'views', 'request', '*', '*')
        Dir.glob(request_cache_path) do |request_subdir|
            info_request_id = File.basename(request_subdir)
            puts "Looking for InfoRequest with id #{info_request_id}" if verbose
            begin
                info_request = InfoRequest.find(info_request_id)
                puts "Got InfoRequest #{info_request_id}" if verbose
                if ! info_request.all_can_view?
                    puts "Deleting cache at #{request_subdir} for hidden/requester_only InfoRequest #{info_request_id}"
                    if ! dryrun
                        FileUtils.rm_rf(request_subdir)
                    end
                end
            rescue ActiveRecord::RecordNotFound
                puts "Deleting cache at #{request_subdir} for deleted InfoRequest #{info_request_id}"
                if ! dryrun
                    FileUtils.rm_rf(request_subdir)
                end
            end
        end
    end

    desc 'Create a CSV file of a random selection of raw emails, for comparing hexdigests'
    task :random_attachments_hexdigests => :environment do

        # The idea is to run this under the Rail 2 codebase, where
        # Tmail was used to extract the attachements, and the task
        # will output all of those file paths in a CSV file, and a
        # list of the raw email files in another.  The latter file is
        # useful so that one can easily tar up the emails with:
        #
        #   tar cvz -T raw-email-files -f raw_emails.tar.gz
        #
        # Then you can switch to the Rails 3 codebase, where
        # attachment parsing is done via
        # recompute_attachments_hexdigests

        require 'csv'

        File.open('raw-email-files', 'w') do |f|
            CSV.open('attachment-hexdigests.csv', 'w') do |csv|

                result = ActiveRecord::Base.connection.execute %q{
                    SELECT
                     im.info_request_id,
                     im.id AS incoming_message_id,
                     im.raw_email_id,
                     fa.id AS foi_attachment_id,
                     fa.filename,
                     fa.url_part_number,
                     fa.hexdigest
                   FROM
                     incoming_messages im,
                     foi_attachments fa
                   WHERE
                     im.id = fa.incoming_message_id
                   ORDER BY
                     (info_request_id, incoming_message_id, url_part_number)}

                columns = result.fields + ['raw_email_filepath']

                csv << columns

                result.each do |row|
                    info_request_id = row['info_request_id']
                    raw_email_directory = File.join(Configuration::raw_emails_location,
                                                    info_request_id[0..2],
                                                    info_request_id)
                    row['raw_email_filepath'] = filepath = File.join(raw_email_directory,
                                                                     row['incoming_message_id'])
                    row_array = columns.map { |c| row[c] }
                    csv << row_array

                    f.puts filepath
                end

            end
        end

    end


    desc 'Check the hexdigests of attachments in emails on disk'
    task :recompute_attachments_hexdigests => :environment do

        require 'csv'
        require 'digest/md5'

        # Make sure that a test public body exists:
        name = "Example Quango"
        pb = PublicBody.find_by_name(name) || PublicBody.new(:name => name)
        pb.update_attributes!(:short_name => name,
                              :last_edit_editor => "mark",
                              :last_edit_comment => "an example edit",
                              :url_name => "example-quango",
                              :request_email => "mark-examplequango@longair.net")

        filename_to_attachments = Hash.new {|h,k| h[k] = []}

        filename_index = nil

        STDERR.puts "Loading CSV file..."

        lines_done = 0
        header_line = true
        CSV.foreach('attachment-hexdigests.csv') do |row|
            if header_line
                columns = row
                headers_as_symbol = columns.map { |e| e.to_sym }
                filename_index = columns.index 'raw_email_filepath'
                OldAttachment = Struct.new *headers_as_symbol
                header_line = false
            else
                filename = row[filename_index]
                filename_to_attachments[filename].push OldAttachment.new *row
            end
            lines_done += 1
            break if lines_done > 30000
        end

        STDERR.puts "done."




        total_attachments = 0
        attachments_with_different_hexdigest = 0
        files_with_different_numbers_of_attachments = 0
        no_tnef_attachments = 0
        no_parts_in_multipart = 0

        multipart_error = "no parts on multipart mail"
        tnef_error = "tnef produced no attachments"

        # Now check each file:
        filename_to_attachments.sort.each do |filename, old_attachments|

            puts "----------------------------------"
            puts "considering filename #{filename}"

            # Currently it doesn't seem to be possible to reuse the
            # attachment parsing code in Alaveteli without saving
            # objects to the database, so reproduce what it does:

            raw_email = nil
            File.open(filename, 'rb') do |f|
                raw_email = f.read
            end

            mail = MailHandler.mail_from_raw_email(raw_email)

            for address in (mail.to || []) + (mail.cc || [])
                # Look for an InfoRequest to add this to...
                info_request_id, hash = InfoRequest._extract_id_hash_from_email address
                if info_request_id > 0
                    puts "going to fetch or create InfoRequest with id #{info_request_id}"
                    info_request = InfoRequest.find_by_id(info_request_id) || InfoRequest.new(:id => info_request_id)
                    info_request.update_attributes!(:title => "Recreated Request with ID #{info_request_id}",
                                                    :prominence => 'normal',
                                                    :external_url => 'http://example.org/',
                                                    :awaiting_description => true,
                                                    :public_body => pb)
                    puts "info_request is #{info_request.inspect} and valid: #{info_request.valid?}"
                    break
                end
                return
            end





            next




            # With this very simple analysis, uudecoded attachments
            # are always wrong, so just ignore any with one of those:
            next if raw_email =~ /^begin.+^`\n^end\n/m

            mail = MailHandler.mail_from_raw_email(raw_email)

            begin
                attachment_attributes = MailHandler.get_attachment_attributes(mail)
            rescue IOError, MailHandler::TNEFParsingError => e
                if e.message == tnef_error
                    puts "#{filename} #{tnef_error}"
                    no_tnef_attachments += 1
                    next
                else
                    raise
                end
            rescue Exception => e
                if e.message == multipart_error
                    puts "#{filename} #{multipart_error}"
                    no_parts_in_multipart += 1
                    next
                else
                    raise
                end
            end

            if attachment_attributes.length != old_attachments.length
                more_or_fewer = attachment_attributes.length > old_attachments.length ? 'more' : 'fewer'
                puts "#{filename} the number of old attachments #{old_attachments.length} didn't match the number of new attachments #{attachment_attributes.length} (#{more_or_fewer})"
                files_with_different_numbers_of_attachments += 1
            else
                old_attachments.each_with_index do |old_attachment, i|
                    total_attachments += 1
                    attrs = attachment_attributes[i]
                    old_hexdigest = old_attachment.hexdigest
                    new_hexdigest = attrs[:hexdigest]
                    new_content_type = attrs[:content_type]
                    old_url_part_number = old_attachment.url_part_number.to_i
                    new_url_part_number = attrs[:url_part_number]
                    if old_url_part_number != new_url_part_number
                        puts "#{i} #{filename} old_url_part_number #{old_url_part_number}, new_url_part_number #{new_url_part_number}"
                    end
                    if old_hexdigest != new_hexdigest
                        body = attrs[:body]
                        # First, if the content type is one of
                        # text/plain, text/html or application/rtf try
                        # changing CRLF to LF and calculating a new
                        # digest - we generally don't worry about
                        # these changes:
                        new_converted_hexdigest = nil
                        if ["text/plain", "text/html", "application/rtf"].include? new_content_type
                            converted_body = body.gsub /\r\n/, "\n"
                            new_converted_hexdigest = Digest::MD5.hexdigest converted_body
                            puts "new_converted_hexdigest is #{new_converted_hexdigest}"
                        end
                        if (! new_converted_hexdigest) || (old_hexdigest != new_converted_hexdigest)
                            puts "#{i} #{filename} old_hexdigest #{old_hexdigest} wasn't the same as new_hexdigest #{new_hexdigest}"
                            puts "  body was of length #{body.length}"
                            puts "  content type was: #{new_content_type}"
                            path = "/tmp/#{new_hexdigest}"
                            f = File.new path, "w"
                            f.write body
                            f.close
                            puts "  wrote body to #{path}"
                            attachments_with_different_hexdigest += 1
                        end
                    end
                end
            end

            puts "total_attachments: #{total_attachments}"
            puts "attachments_with_different_hexdigest: #{attachments_with_different_hexdigest}"
            puts "files_with_different_numbers_of_attachments: #{files_with_different_numbers_of_attachments}"
            puts "no_tnef_attachments: #{no_tnef_attachments}"
            puts "no_parts_in_multipart: #{no_parts_in_multipart}"

        end


    end

end
