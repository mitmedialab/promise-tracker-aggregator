require 'sinatra'
require 'sinatra/config_file'
require 'mongo'
require 'mongoid'
require 'pry'
require 'json/ext'
require 'pry'

class Setting
  include Mongoid::Document
  
  field :installation_id, type: Integer
end

class Survey
  include Mongoid::Document

  field :id, type: Integer
  field :title, type: String
  field :code, type: Integer
  field :campaign_id, type: Integer
  field :status, type: String
  field :start_date, type: Time
  field :inputs, type: Array

end

class Response
  include Mongoid::Document

  field :installation_id, type: Integer
  field :timestamp, type: Integer
  field :survey_id, type: Integer
  field :answers, type: Array
  field :locationstamp, type: Hash
end

class PTApi < Sinatra::Base
  register Sinatra::ConfigFile
  config_file File.dirname(__FILE__) + '/../config.yml'

  require File.join(root, '/config/initializers/mongoid.rb')

  configure do
    set :public_folder, File.dirname(__FILE__) + '/../public/'
    enable :static, :logging

    Mongoid.configure do |config|
      config.clients.default = {
        uri: settings.db_connection_string,
      }
    end
  end

  before do
    headers 'Access-Control-Allow-Origin' => '*'
    content_type 'application/json'

    if request.post?
      error 401 unless env['HTTP_AUTHORIZATION'] == settings.access_key
    end
  end

  options '*' do
    response.headers['Allow'] = 'HEAD,GET,POST,PUT,DELETE,OPTIONS'
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Authorization, Accept, Cache-Control'
    200
  end

  get '/getId' do
    setting = Setting.first
    id = setting.installation_id

    id += 1
    setting.installation_id = id
    if setting.save
      {
        status: 'success',
        payload: {installation_id: id}
      }.to_json
    end
  end

  get '/surveys' do
    surveys = Survey.all

    {
      status: 'success',
      payload: surveys
    }.to_json
  end

  post '/surveys/:status' do
    data = JSON.parse(request.body.read)
    survey =  Survey.find(data['id'])

    if survey
      survey.set(data)
    else
      survey = Survey.create(data)
    end

    survey.reload
    survey.status = params[:status]
    survey.start_date = Time.now.midnight
    Response.destroy_all({survey_id: survey.id})

    if survey.save
      {
        status: 'success',
        payload: { id: survey.id, start_date: survey.start_date }
      }.to_json
    else
      {
        status: 'error',
        error_code: 13,
        error_message: 'Survey could not be saved because id is already taken'
      }.to_json
    end
  end

  get '/surveys/:code' do
    survey = Survey.where(code: params[:code].to_i).first

    if survey
      {
        status: 'success',
        payload: survey
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  put '/surveys/:code/close' do
    survey = Survey.where(code: params[:code].to_i).first
    
    if survey
      survey.status = 'closed'
      survey.save
      { 
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else 
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/responses' do
    survey = Survey.where(code: params[:code].to_i).first

    if survey
      {
        status: 'success',
        payload: Response.where(survey_id: survey.id).sort(:timestamp.desc).to_a
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/survey-with-responses' do
    survey = Survey.where(code: params[:code].to_i).first

    if survey
      {
        status: 'success',
        payload: {
          survey: survey,
          responses: Response.where(survey_id: survey.id).sort(:timestamp.desc).to_a
        }
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/responses' do
    {
      status: 'success',
      payload: Response.all.limit(5000).to_a
    }.to_json
  end

  post '/responses' do
    response_data = JSON.parse(params[:response])
    survey = Survey.find(response_data['survey_id'].to_i)
    duplicate = Response.where(
      installation_id: response_data['installation_id'],
      timestamp: response_data['timestamp']
    ).first

    if survey && !duplicate
      if survey.status != 'closed'
        response = Response.create(response_data.except("status"))
        {
          status: 'success',
          payload: {id: response.id.to_s}
        }.to_json
      else
        {
          status: 'error',
          error_code: 14,
          error_message: 'Response could not be posted because survey is closed'
        }.to_json
      end
    elsif duplicate
      {
        status: 'success',
        payload: {id: duplicate.id.to_s}
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  post '/upload_image' do
    original_name = params[:file][:filename]
    filename = SecureRandom.urlsafe_base64
    filename = filename + original_name[original_name.rindex('.')..-1]
    file = params[:file][:tempfile]

    begin
      File.open(settings.public_folder + filename, 'wb') do |f|
        f.write(file.read)
        response = Response.find(params[:id])
        if response
          input = response[:answers].select {|input| input['id'] == params[:input_id].to_i}.first
          input_index = response.answers.find_index(input)
          if input
            #Account for previous mobile versions where only one image per question was possible
            value = response.answers[input_index]['value']
            if value.kind_of?(Array)
              image_index = nil
              value.each_with_index do |s, i|
                image_index = i if s.exclude?(settings.base_url) && s.split('/')[-1] == original_name
              end
              value[image_index] = "#{settings.base_url}/#{filename}" if image_index
            else
              value = "#{settings.base_url}/#{filename}"
            end

            if response.save
              {
                status: 'success',
                payload: {id: params[:id], input_id: params[:input_id]}
              }.to_json
            else
              {
                status: 'error',
                error_code: 16,
                error_message: 'File Upload: cannot update response object'
              }.to_json
            end
          else
            {
              status: 'error',
              error_code: 15,
              error_message: 'File Upload: cannot find the corresponding input'
            }.to_json 
          end
        else
          {
            status: 'error',
            error_code: 14,
            error_message: 'File Upload: cannot find the response'
          }.to_json
        end
      end # post: file.open
    rescue IOError => e
      return {
        status: 'error',
        error_code: 17,
        error_message: 'File open failed'
      }.to_json
    ensure
      file.close unless file == nil
    end # post: try catch file.open error
  end # post: upload_image
end