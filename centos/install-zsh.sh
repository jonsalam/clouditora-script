#!/bin/bash

function install_plugin() {
  URL=$1
  NAME=$(echo "$URL" | awk -F '/' '{print $NF}' | awk -F '.git' '{print $1}')
  if [[ ! -d ~/.oh-my-zsh/plugins/$NAME ]]; then
    git clone --depth 1 "$URL" ~/.oh-my-zsh/plugins/"$NAME"
  fi
  if [[ $(sed -n "/$NAME/p" ~/.zshrc) == '' ]]; then
    sed -i "s/^plugins=([^)]*/& $NAME/" ~/.zshrc
  fi
}

yum install -y zsh fontconfig git
command -V chsh || {
  yum install -y util-linux-user
}
chsh -s /bin/zsh
echo 'yes' | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# plugins
install_plugin https://github.com/zsh-users/zsh-autosuggestions.git
install_plugin https://github.com/zsh-users/zsh-completions.git
install_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git

# fonts
mkdir -p /user/share/fonts
curl https://raw.githubusercontent.com/powerline/powerline/develop/font/PowerlineSymbols.otf -o PowerlineSymbols.otf
mv PowerlineSymbols.otf /user/share/fonts/
curl https://raw.githubusercontent.com/powerline/powerline/develop/font/10-powerline-symbols.conf -o 10-powerline-symbols.conf
mkdir -p /etc/fonts/conf.d
mv 10-powerline-symbols.conf /etc/fonts/conf.d/
fc-cache -vf /usr/share/fonts

# powerline
./install-python3.sh
pip3 install powerline-status
PYTHON_PATH=$(python3 -V | grep -Eo '3\.[0-9]+')
grep -q 'powerline-daemon -q' ~/.zshrc
if [[ $? -eq 1 ]]; then
  cat <<EOF >>~/.zshrc

# powerline
if [[ -f $(which powerline-daemon) ]];then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/local/lib/python$PYTHON_PATH/site-packages/powerline/bindings/zsh/powerline.zsh
fi
export TERM="screen-256color"
EOF
fi

zsh
