class QuestionsController < ApplicationController
  before_action :require_login
  
  PER = 5
  
  # 質問の新規作成ページを表示
  def new
    @question = Question.new
  end
  
  # 新しい質問をデータベースに登録
  def create
    @question = Question.new(question_params_create)
    @question.user_id = current_user.id
    if @question.save
      redirect_to home_path, success: '質問を作成しました'
    else
      flash.now[:danger] = '質問を作成できませんでした 質問タイトルと内容を確認してください'
      render :new
    end
  end

  # 全てのユーザーの質問一覧ページを表示
  def index
    if params[:search].present?
      questions_source = Question.where('status > 0 AND deletion_flg = 0')\
        .order('created_at DESC').includes(:user).to_a
      
      # キーワード(スペースでAND指定)を含むものだけを抜き出す
      # 参照 : https://qiita.com/nao58/items/bf5d017a06fc33da9e3b
      keywords = params[:search].split(/[[:blank:]]+/)
      questions_source.select! do |s|
        keywords.all? { |k| s.title.include?(k) or s.content.include?(k) }
      end
      
      @questions = Kaminari.paginate_array(questions_source).page(params[:page]).per(PER)
      
    elsif @current_user.admin_auth != 0
      # 管理者権限がある場合は下書きと削除済みの質問も表示
      @questions = Question.all.order('created_at DESC')\
        .includes(:user).page(params[:page]).per(PER)
    else
      @questions = Question.where('status > 0 AND deletion_flg = 0')\
        .order('created_at DESC').includes(:user).page(params[:page]).per(PER)
    end
  end
  
  # 特定ユーザーの作成した質問一覧ページを表示  
  def user_questions_index

    @user = User.find_by(id: params[:id])
    if @user.nil?
      redirect_to home_path, danger: '存在しないユーザーです'
    end
    
    if @user.id == @current_user.id || @current_user.admin_auth != 0
      # 同一ユーザの質問、または管理者権限では下書きも表示
      @questions = Question.where(user_id: params[:id], deletion_flg: 0)\
        .order('created_at DESC').includes(:user).page(params[:page]).per(PER)
    else
      # 他のユーザの質問も表示できるが、下書きは表示しない
      @questions = Question.where(\
        "user_id = #{params[:id].to_i} AND status > 0 AND deletion_flg = 0")\
        .order('created_at DESC').page(params[:page]).includes(:user).per(PER)
    end
  end
  
  # 質問の詳細ページを表示
  def show
    find_a_question
    if @question.nil?
      redirect_to questions_index_path, \
        danger: '指定された質問がありません'
    end
    
    # 投稿者のアカウントで閲覧した場合は、すべての回答の既読フラグを更新
    if @current_user.id == @question.user_id
      @answers = Answer.where(question_id: params[:id])
      @answers.each do |a|
        a.update_attribute(:already_read, 1)
      end
    end
    
    # 表示する情報関連
    if @question.best_answer.nil?
      @best_answer = nil
      @answers = Answer.where(question_id: params[:id], deletion_flg: 0)\
        .order('updated_at DESC').includes(:user)
    else
      # ベストアンサーが指定されている場合
      @best_answer = Answer.where(id: @question.best_answer).includes(:user).first
    
      @answers = Answer.where(question_id: params[:id], deletion_flg: 0)\
        .where.not(id: @question.best_answer).order('updated_at DESC').includes(:user)
      # binding.pry
    end
  end
  
  # 質問の編集ページを表示
  def edit
    find_a_question
    if @question.nil?
      redirect_to questions_index_path, \
        danger: '指定された質問がありません'
    end
    
    @answers = Answer.where(question_id: params[:id], deletion_flg: 0)\
      .order('updated_at DESC').includes(:user)
  end
  
  # データベースに質問の更新を指示
  def update
    find_a_question
    if @question.nil?
      redirect_to questions_index_path, \
        danger: '指定された質問がありません'
    end
    
    if @question.user_id == @current_user.id || @current_user.admin_auth != 0
      if @question.update_attributes(question_params_update)
        redirect_to home_path, success: '更新が完了しました'
      else
        redirect_to edit_question_path(params[:id]),\
          danger: '更新に失敗しました。必須項目を確認してください'
      end
    else
      redirect_to show_question_path(params[:id]),
        danger: '質問の編集は質問者または管理者のみが行えます'
    end
  end
  
  # 質問の削除確認ページを表示
  def confirm_deletion
    find_a_question
  end
  
  # 質問の削除を実行
  def destroy
    find_a_question
    @question.title = "削除された質問"
    @question.content = "この質問は削除されました。"
    @question.image = ""
    @question.best_answer = nil
    @question.deletion_flg = 1

    if @question.user_id == @current_user.id || @current_user.admin_auth != 0
      if @question.save
        redirect_to home_path, success: '質問を削除しました'
      else
        redirect_to confirm_delete_question_path(params[:id]),\
          danger: '質問の削除に失敗しました'
      end
    else
      redirect_to show_question_path(params[:id]),
        danger: '質問の削除は質問者または管理者のみが行えます'
    end
  end
  
  private
  # 質問の新規作成時に使用するStrong Parameter
  def question_params_create
    params.require(:question).permit(:title, :content, :status)
  end
  
  # 質問の更新時に使用するStrong Parameter
  def question_params_update
    params.require(:question).permit(:title, :content, :status, :best_answer)
  end
  
  # params[:id]に対応する質問レコードをデータベースから取得
  def find_a_question
    @question = Question.find_by(id: params[:id])
  end
end
