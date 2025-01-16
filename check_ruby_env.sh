#!/bin/bash

# Ruby开发环境检查脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 计数器
pass_count=0
fail_count=0
warning_count=0

# 配置参数
MIN_RUBY_VERSION="2.7.0"
MIN_MEMORY_GB=4
MIN_DISK_SPACE_GB=10
MIN_CPU_CORES=2

# 日志文件
LOG_FILE="ruby_env_check_$(date +%Y%m%d_%H%M%S).log"

# 基础函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_header() {
    log "\n${BLUE}=== $1 ===${NC}"
}

check() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        log "${GREEN}[✓] $message${NC}"
        ((pass_count++))
    else
        log "${RED}[×] $message${NC}"
        ((fail_count++))
    fi
}

warning() {
    log "${YELLOW}[!] $1${NC}"
    ((warning_count++))
}

info() {
    log "${CYAN}[i] $1${NC}"
}

# 版本比较函数
version_compare() {
    if [[ "$1" == "$2" ]]; then return 0; fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then return 1; fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then return 2; fi
    done
    return 0
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "==============================================="
echo "Ruby 开发环境检查工具"
echo "检查开始时间: $(date)"
echo "==============================================="

# 1. 系统基础检查
log_header "系统基础检查"

# 操作系统信息
info "操作系统信息："
cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2

# CPU检查
cpu_cores=$(nproc)
cpu_model=$(cat /proc/cpuinfo | grep "model name" | head -n1 | cut -d: -f2)
info "CPU型号:$cpu_model"
info "CPU核心数: $cpu_cores"
if [ "$cpu_cores" -lt "$MIN_CPU_CORES" ]; then
    check 1 "CPU核心数($cpu_cores)小于建议值($MIN_CPU_CORES)"
else
    check 0 "CPU核心数符合要求($cpu_cores cores)"
fi

# 内存检查
total_mem=$(free -g | awk '/^Mem:/{print $2}')
info "系统总内存: ${total_mem}GB"
if [ "$total_mem" -lt "$MIN_MEMORY_GB" ]; then
    check 1 "系统内存(${total_mem}GB)小于建议值(${MIN_MEMORY_GB}GB)"
else
    check 0 "系统内存符合要求(${total_mem}GB)"
fi

# 2. Ruby环境检查
log_header "Ruby环境检查"

# Ruby版本检查
if command_exists ruby; then
    ruby_version=$(ruby -v | cut -d' ' -f2)
    info "Ruby版本: $ruby_version"
    version_compare "$ruby_version" "$MIN_RUBY_VERSION"
    if [ $? -eq 2 ]; then
        check 1 "Ruby版本($ruby_version)低于建议值($MIN_RUBY_VERSION)"
    else
        check 0 "Ruby版本符合要求($ruby_version)"
    fi
else
    check 1 "Ruby未安装"
fi

# RubyGems检查
if command_exists gem; then
    gem_version=$(gem -v)
    check 0 "RubyGems已安装 (版本: $gem_version)"
    
    # 检查重要的gems
    important_gems=("bundler" "rake" "rails" "rspec" "puma" "sidekiq" "rubocop")
    for gem in "${important_gems[@]}"; do
        if gem list -i "^$gem$" > /dev/null 2>&1; then
            version=$(gem list "^$gem$" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
            check 0 "$gem已安装 (版本: $version)"
        else
            check 1 "$gem未安装"
        fi
    done
else
    check 1 "RubyGems未安装"
fi

# rbenv检查
if command_exists rbenv; then
    rbenv_version=$(rbenv -v | cut -d' ' -f2)
    check 0 "rbenv已安装 (版本: $rbenv_version)"
    
    # 检查rbenv初始化
    # 检查多个可能的配置文件
    config_files=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
        "$HOME/.zshrc"
        "$HOME/.zprofile"
        "$HOME/.zshenv"
    )
    
    rbenv_initialized=0
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ] && (grep -q 'rbenv init' "$config_file" || grep -q 'eval "$(rbenv init' "$config_file"); then
            rbenv_initialized=1
            check 0 "rbenv在 $config_file 中已初始化"
            break
        fi
    done
    
    # 另外通过环境变量和 rbenv 命令检查是否实际已初始化
    if [ $rbenv_initialized -eq 0 ]; then
        if command -v rbenv >/dev/null 2>&1 && rbenv root >/dev/null 2>&1; then
            check 0 "rbenv运行正常（虽然未在常见配置文件中找到初始化配置）"
        else
            check 1 "rbenv未在shell中初始化"
            info "建议添加以下内容到你的shell配置文件："
            info "eval \"\$(rbenv init -)\""
        fi
    fi
else
    warning "rbenv未安装，建议使用版本管理工具"
fi


# 3. 开发依赖检查
log_header "开发依赖检查"

check_package() {
    local package=$1
    if dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -q "install ok installed"; then
        local version=$(dpkg-query -W -f='${Version}\n' "$package" 2>/dev/null)
        check 0 "$package已安装 (版本: $version)"
        return 0
    else
        check 1 "$package未安装"
        return 1
    fi
}

# 检查基础开发工具
dev_tools=("git" "gcc" "g++" "make" "automake" "autoconf" "libssl-dev" "zlib1g-dev" "sqlite3" "libsqlite3-dev")
for tool in "${dev_tools[@]}"; do
    check_package "$tool"
done



# 4. Web服务器检查
log_header "Web服务器检查"

# Nginx检查
if command_exists nginx; then
    nginx_version=$(nginx -v 2>&1 | cut -d'/' -f2)
    check 0 "Nginx已安装 (版本: $nginx_version)"
    if systemctl is-active nginx >/dev/null 2>&1; then
        check 0 "Nginx服务运行正常"
    else
        check 1 "Nginx服务未运行"
    fi
else
    warning "Nginx未安装"
fi

# 5. Node.js环境检查 (用于前端开发)
log_header "Node.js环境检查"

if command_exists node; then
    node_version=$(node -v | cut -c2-)
    check 0 "Node.js已安装 (版本: $node_version)"
    
    if command_exists npm; then
        npm_version=$(npm -v)
        check 0 "npm已安装 (版本: $npm_version)"
    else
        check 1 "npm未安装"
    fi
    
    if command_exists yarn; then
        yarn_version=$(yarn -v)
        check 0 "yarn已安装 (版本: $yarn_version)"
    else
        warning "yarn未安装"
    fi
else
    warning "Node.js未安装"
fi

# 6. Ruby性能优化检查
log_header "Ruby性能优化检查"

# 检查 jemalloc
if ldconfig -p | grep -q "libjemalloc.so"; then
    check 0 "jemalloc已安装"
else
    warning "建议安装jemalloc以优化Ruby内存管理"
fi

# 检查Ruby编译参数
if ruby -r rbconfig -e "puts RbConfig::CONFIG['CFLAGS']" | grep -q "O3"; then
    check 0 "Ruby使用O3优化编译"
else
    warning "Ruby未使用最高级别优化编译"
fi

# 7. 开发工具链检查
log_header "开发工具链检查"

# Shell配置检查
for rc in ".bashrc" ".zshrc"; do
    if [ -f "$HOME/$rc" ]; then
        if grep -q "RAILS_ENV" "$HOME/$rc"; then
            check 0 "在$rc中发现Rails环境变量配置"
        else
            warning "$rc中未设置Rails环境变量"
        fi
    fi
done

# Git配置检查
if command_exists git; then
    if [ -f "$HOME/.gitconfig" ]; then
        check 0 "Git全局配置文件存在"
        # 检查必要的Git配置
        for config in "user.name" "user.email" "core.editor"; do
            if git config --global --get "$config" >/dev/null; then
                check 0 "Git $config 已配置"
            else
                check 1 "Git $config 未配置"
            fi
        done
    else
        check 1 "Git全局配置文件不存在"
    fi
fi



# 8. 网络工具检查
log_header "网络工具检查"

network_tools=("curl" "wget" "netstat" "nc" "dig" "nmap")
for tool in "${network_tools[@]}"; do
    if command_exists "$tool"; then
        version=$("$tool" --version 2>&1 | head -n1)
        check 0 "$tool已安装 ($version)"
    else
        warning "$tool未安装"
    fi
done


# 9. 项目特定检查
log_header "项目特定检查"

# 检查常用目录结构
directories=("app" "config" "db" "lib" "log" "public" "spec" "test" "tmp" "vendor")
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        check 0 "项目目录 $dir 存在"
    else
        info "项目目录 $dir 不存在"
    fi
done

# 检查配置文件
config_files=("config/database.yml" "config/application.yml" "config/master.key" ".env")
for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
        check 0 "配置文件 $file 存在"
    else
        warning "配置文件 $file 不存在"
    fi
done

# 10. 开发环境变量检查
log_header "环境变量检查"

required_vars=("RAILS_ENV" "RACK_ENV" "DATABASE_URL" "REDIS_URL" "SECRET_KEY_BASE")
for var in "${required_vars[@]}"; do
    if [ -n "${!var}" ]; then
        check 0 "环境变量 $var 已设置"
    else
        warning "环境变量 $var 未设置"
    fi
done

# 11. 日志管理检查
log_header "日志管理检查"

# Logrotate配置检查
if [ -f "/etc/logrotate.d/rails" ]; then
    check 0 "Rails日志轮转配置存在"
else
    warning "Rails日志轮转配置不存在"
fi



# 总结报告
echo -e "\n==============================================="
echo "环境检查完成！"
echo "通过检查项: $pass_count"
echo "警告项: $warning_count"
echo "失败检查项: $fail_count"
echo "详细日志已保存至: $LOG_FILE"
echo "==============================================="

# 如果有失败项，提供建议
if [ $fail_count -gt 0 ]; then
    echo -e "\n${YELLOW}建议操作：${NC}"
    echo "1. 安装缺失的开发依赖："
    echo "   sudo apt-get install build-essential libssl-dev zlib1g-dev"
    echo "2. 安装Ruby版本管理工具："
    echo "   curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-installer | bash"
    echo "3. 安装Web服务器："
    echo "   sudo apt-get install nginx"
    echo "4. 安装Node.js (如需前端开发)："
    echo "   curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
    echo "   sudo apt-get install nodejs"
fi

exit $fail_count
